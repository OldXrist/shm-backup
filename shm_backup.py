import asyncio
import os
import subprocess
import sys
from datetime import datetime
from dotenv import load_dotenv
from aiogram import Bot, Dispatcher, Router, F
from aiogram.filters import Command
from aiogram.types import BufferedInputFile, InlineKeyboardMarkup, InlineKeyboardButton, CallbackQuery

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(SCRIPT_DIR, ".env"))

SHM_DIR = os.getenv("SHM_DIR", "/opt/shm")
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
TELEGRAM_CHAT_ID = int(os.getenv("TELEGRAM_CHAT_ID", "0"))

if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
    print("Error: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID missing in .env", file=sys.stderr)
    sys.exit(1)

router = Router()


def generate_backup() -> tuple[bytes | None, str]:
    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    filename = f"shm_backup_{timestamp}.sql"
    cmd = "docker compose exec -T mysql /bin/bash -c 'MYSQL_PWD=${MYSQL_ROOT_PASSWORD} mysqldump -u root shm'"

    try:
        result = subprocess.run(
            cmd,
            shell=True,
            cwd=SHM_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True
        )
        return result.stdout, filename
    except subprocess.CalledProcessError as e:
        print(f"Error executing mysqldump: {e.stderr.decode('utf-8')}", file=sys.stderr)
        return None, filename


def get_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [InlineKeyboardButton(text="⚡ Create Backup Now", callback_data="run_backup")],
            [InlineKeyboardButton(text="ℹ️ Status", callback_data="check_status")]
        ]
    )


async def run_cli_backup():
    bot = Bot(token=TELEGRAM_BOT_TOKEN)
    data, filename = generate_backup()
    if data:
        document = BufferedInputFile(data, filename=filename)
        caption = f"📦 <b>SHM Database Backup</b>\n📅 <code>{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</code>"
        await bot.send_document(chat_id=TELEGRAM_CHAT_ID, document=document, caption=caption, parse_mode="HTML")
        print(f"Backup sent: {filename}")
    else:
        await bot.send_message(chat_id=TELEGRAM_CHAT_ID, text="❌ <b>SHM Backup Failed!</b> Check server logs.",
                               parse_mode="HTML")
        print("Backup failed.")
    await bot.session.close()


@router.message(Command("start"), F.chat.id == TELEGRAM_CHAT_ID)
@router.message(Command("backup"), F.chat.id == TELEGRAM_CHAT_ID)
async def cmd_start(message):
    await message.answer(
        "🛠 <b>SHM Panel Backup Manager</b>\nClick below to generate a fresh database dump.",
        reply_markup=get_keyboard(),
        parse_mode="HTML"
    )


@router.callback_query(F.data == "run_backup", F.message.chat.id == TELEGRAM_CHAT_ID)
async def handle_backup_callback(callback: CallbackQuery):
    await callback.answer("Generating backup...")
    await callback.message.edit_text("⏳ <i>Running mysqldump...</i>", parse_mode="HTML")

    data, filename = generate_backup()
    if data:
        document = BufferedInputFile(data, filename=filename)
        caption = f"📦 <b>SHM Database Backup</b>\n📅 <code>{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</code>"
        await callback.message.answer_document(document=document, caption=caption, parse_mode="HTML",
                                               reply_markup=get_keyboard())
    else:
        await callback.message.answer("❌ <b>Backup failed!</b> Check container status.", reply_markup=get_keyboard(),
                                      parse_mode="HTML")


@router.callback_query(F.data == "check_status", F.message.chat.id == TELEGRAM_CHAT_ID)
async def handle_status_callback(callback: CallbackQuery):
    await callback.answer()
    await callback.message.answer("✅ Backup service is running.", reply_markup=get_keyboard())


async def run_bot():
    bot = Bot(token=TELEGRAM_BOT_TOKEN)
    dp = Dispatcher()
    dp.include_router(router)
    print("SHM Backup Telegram Bot started...")
    await dp.start_polling(bot)


if __name__ == "__main__":
    # Execution via the `shm-backup` command runs CLI backup mode exclusively
    if os.path.basename(sys.argv[0]) == "shm-backup":
        asyncio.run(run_cli_backup())
    else:
        asyncio.run(run_bot())
