"""Explicit initial database setup and local administrator provisioning."""

import argparse, getpass, os
import pyotp
from cryptography.fernet import Fernet
from .db import connect, initialize, users, one, uid
from .security import config, ph


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["init-db", "create-admin", "seed-demo"])
    args = parser.parse_args()
    settings = config()
    engine = connect(os.environ["DATABASE_URL"])
    if args.command == "seed-demo":
        from pathlib import Path
        from .seed import seed_demo

        print(
            "Seeded:", seed_demo(engine, Path(os.environ.get("MEDIA_ROOT", "./media")))
        )
        return
    if args.command == "init-db":
        initialize(engine)
        print("Database initialized. Back up before future schema upgrades.")
        return
    username = input("Admin login: ").strip().lower()
    import re

    if not re.fullmatch(r"[a-z0-9_.@+-]{3,120}", username):
        raise SystemExit("Invalid login")
    password = getpass.getpass("Password (12+ characters): ")
    if (
        len(password) < 12
        or len(password) > 128
        or password != getpass.getpass("Repeat password: ")
    ):
        raise SystemExit("Password invalid or mismatched")
    secret = pyotp.random_base32()
    with engine.begin() as c:
        if one(c, users, users.c.username == username):
            raise SystemExit("Login exists")
        c.execute(
            users.insert().values(
                id=uid(),
                username=username,
                name="Super Admin",
                password=ph.hash(password),
                role="super_admin",
                totp=Fernet(settings["key"].encode()).encrypt(secret.encode()).decode(),
            )
        )
    print("Store in authenticator now; do not share or commit this URI:")
    print(pyotp.TOTP(secret).provisioning_uri(name=username, issuer_name="Baxshi AI"))


if __name__ == "__main__":
    main()
