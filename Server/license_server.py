"""Сервер лицензий «Сумерки» внутри Telegram-бота @twilight_xbot.

* HTTP  POST /activate  {"key": "TW-...", "device": "<uuid>"} — вызывает игра.
    200 {"license": b64(json), "signature": b64(ed25519)} — ключ привязан к этому устройству
    404 ключа нет · 409 ключ уже привязан к другому устройству · 403 ключ отозван
* Бот (только для ADMIN_IDS): /newkeys N, /keys, /info KEY, /reset KEY, /revoke KEY, /unrevoke KEY.

Переменные окружения:
  LICENSE_PRIVATE_KEY  — из keygen.py (base64), обязательно
  BOT_TOKEN            — токен бота (без него работает только HTTP)
  ADMIN_IDS            — Telegram ID админов через запятую
  PORT                 — порт HTTP (по умолчанию 8080)
  DB_PATH              — файл базы (по умолчанию licenses.db)
"""
import asyncio
import base64
import json
import os
import secrets
import sqlite3
import time

from aiohttp import web
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

DB_PATH = os.environ.get("DB_PATH", "licenses.db")
PORT = int(os.environ.get("PORT", "8080"))
ADMIN_IDS = {int(x) for x in os.environ.get("ADMIN_IDS", "").replace(" ", "").split(",") if x}
PRIVATE_KEY = Ed25519PrivateKey.from_private_bytes(base64.b64decode(os.environ["LICENSE_PRIVATE_KEY"]))
ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # без 0/O и 1/I — не перепутать при вводе


# ---------- база ----------

def db() -> sqlite3.Connection:
    con = sqlite3.connect(DB_PATH)
    con.execute("""CREATE TABLE IF NOT EXISTS keys (
        key TEXT PRIMARY KEY,
        device TEXT,
        activated_at INTEGER,
        created_at INTEGER NOT NULL,
        revoked INTEGER NOT NULL DEFAULT 0,
        note TEXT)""")
    return con


def new_key() -> str:
    groups = ["".join(secrets.choice(ALPHABET) for _ in range(4)) for _ in range(3)]
    return "TW-" + "-".join(groups)


def make_keys(n: int, note: str = "") -> list[str]:
    con = db()
    out = []
    while len(out) < n:
        k = new_key()
        try:
            con.execute("INSERT INTO keys (key, created_at, note) VALUES (?, ?, ?)", (k, int(time.time()), note))
            out.append(k)
        except sqlite3.IntegrityError:
            continue
    con.commit()
    return out


def sign_license(key: str, device: str) -> dict:
    payload = json.dumps({"key": key, "device": device, "issued": int(time.time())},
                         separators=(",", ":")).encode()
    return {"license": base64.b64encode(payload).decode(),
            "signature": base64.b64encode(PRIVATE_KEY.sign(payload)).decode()}


# ---------- HTTP для игры ----------

async def activate(request: web.Request) -> web.Response:
    try:
        body = await request.json()
        key = str(body["key"]).strip().upper()
        device = str(body["device"]).strip()
    except Exception:
        return web.json_response({"error": "bad_request"}, status=400)
    if not key or not device or len(device) > 64:
        return web.json_response({"error": "bad_request"}, status=400)

    con = db()
    row = con.execute("SELECT device, revoked FROM keys WHERE key = ?", (key,)).fetchone()
    if row is None:
        return web.json_response({"error": "not_found"}, status=404)
    bound, revoked = row
    if revoked:
        return web.json_response({"error": "revoked"}, status=403)
    if bound and bound != device:
        return web.json_response({"error": "used_elsewhere"}, status=409)
    if not bound:
        # Привязываем атомарно: только если ключ всё ещё свободен.
        cur = con.execute("UPDATE keys SET device = ?, activated_at = ? WHERE key = ? AND device IS NULL",
                          (device, int(time.time()), key))
        con.commit()
        if cur.rowcount == 0:
            again = con.execute("SELECT device FROM keys WHERE key = ?", (key,)).fetchone()
            if again and again[0] != device:
                return web.json_response({"error": "used_elsewhere"}, status=409)
    return web.json_response(sign_license(key, device))


async def health(_: web.Request) -> web.Response:
    return web.Response(text="ok")


def http_app() -> web.Application:
    app = web.Application()
    app.router.add_post("/activate", activate)
    app.router.add_get("/health", health)
    return app


# ---------- команды бота ----------

async def run_bot():
    token = os.environ.get("BOT_TOKEN")
    if not token:
        print("BOT_TOKEN не задан — работает только HTTP /activate")
        return
    from aiogram import Bot, Dispatcher, F
    from aiogram.filters import Command, CommandObject
    from aiogram.types import Message

    bot = Bot(token)
    dp = Dispatcher()
    admin = F.from_user.id.in_(ADMIN_IDS)

    @dp.message(Command("start"))
    async def start(m: Message):
        await m.answer("Сумерки — игра для iPad. Ключ активирует игру на одном устройстве.")

    @dp.message(Command("newkeys"), admin)
    async def newkeys(m: Message, command: CommandObject):
        n = max(1, min(100, int(command.args or 1))) if (command.args or "1").isdigit() else 1
        keys = make_keys(n, note=f"by {m.from_user.id}")
        await m.answer("Новые ключи:\n" + "\n".join(f"<code>{k}</code>" for k in keys), parse_mode="HTML")

    @dp.message(Command("keys"), admin)
    async def keys(m: Message):
        con = db()
        total, used, revoked = con.execute(
            "SELECT COUNT(*), COUNT(device), SUM(revoked) FROM keys").fetchone()
        rows = con.execute("SELECT key, device, revoked FROM keys ORDER BY created_at DESC LIMIT 30").fetchall()
        lines = [f"{k} — {'отозван' if r else ('привязан' if d else 'свободен')}" for k, d, r in rows]
        await m.answer(f"Всего {total}, активировано {used}, отозвано {revoked or 0}\n\n" + "\n".join(lines))

    @dp.message(Command("info"), admin)
    async def info(m: Message, command: CommandObject):
        k = (command.args or "").strip().upper()
        row = db().execute("SELECT device, activated_at, revoked, note FROM keys WHERE key = ?", (k,)).fetchone()
        if not row:
            await m.answer("Ключ не найден")
            return
        d, at, r, note = row
        when = time.strftime("%Y-%m-%d %H:%M", time.gmtime(at)) + " UTC" if at else "—"
        await m.answer(f"{k}\nустройство: {d or '—'}\nактивирован: {when}\nотозван: {'да' if r else 'нет'}\n{note or ''}")

    async def update(m: Message, k: str, sql: str, done: str):
        cur = db()
        res = cur.execute(sql, (k.strip().upper(),))
        cur.commit()
        await m.answer(done if res.rowcount else "Ключ не найден")

    @dp.message(Command("reset"), admin)
    async def reset(m: Message, command: CommandObject):
        await update(m, command.args or "", "UPDATE keys SET device = NULL, activated_at = NULL WHERE key = ?",
                     "Привязка сброшена — ключ можно активировать на новом устройстве")

    @dp.message(Command("revoke"), admin)
    async def revoke(m: Message, command: CommandObject):
        await update(m, command.args or "", "UPDATE keys SET revoked = 1 WHERE key = ?", "Ключ отозван")

    @dp.message(Command("unrevoke"), admin)
    async def unrevoke(m: Message, command: CommandObject):
        await update(m, command.args or "", "UPDATE keys SET revoked = 0 WHERE key = ?", "Ключ снова активен")

    await dp.start_polling(bot)


async def main():
    db().close()
    runner = web.AppRunner(http_app())
    await runner.setup()
    await web.TCPSite(runner, "0.0.0.0", PORT).start()
    print(f"HTTP: http://0.0.0.0:{PORT}/activate")
    await run_bot()
    await asyncio.Event().wait()


if __name__ == "__main__":
    asyncio.run(main())
