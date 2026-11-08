import hmac
import ipaddress
import json
import logging
import os
import secrets
import sqlite3
import string
import subprocess

import requests
import yaml
from flask import Flask, jsonify, make_response, request, send_from_directory
from werkzeug.exceptions import HTTPException

import auth

app = Flask(__name__)
app.secret_key = auth.SECRET_KEY
app.config.update(
    SESSION_COOKIE_SECURE=True,
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
)
log = logging.getLogger(__name__)

DB_PATH = os.environ.get("DB_PATH", "/data/app.db")
FILES_DIR = os.path.abspath(os.environ.get("FILES_DIR", "files"))
HOST = os.environ.get("FLASK_HOST", "127.0.0.1")
PORT = int(os.environ.get("FLASK_PORT", "8080"))
ADMIN_TOKEN = os.environ.get("ADMIN_TOKEN", "")
# Ressources distantes autorisees pour /fetch (URL exactes, separees par des virgules)
FETCH_ALLOWLIST = [u.strip() for u in os.environ.get("FETCH_ALLOWLIST", "").split(",") if u.strip()]

PING_BIN = "/usr/bin/ping"
HOSTNAME_CHARS = frozenset(string.ascii_letters + string.digits + "-")
ERR_BAD_REQUEST = "bad request"


def db():
    return sqlite3.connect(DB_PATH)


def seed_password(env_name):
    """Mot de passe des comptes de demonstration : fourni par l'environnement, sinon aleatoire."""
    return os.environ.get(env_name) or secrets.token_urlsafe(16)


def init_db():
    os.makedirs(os.path.dirname(DB_PATH) or ".", exist_ok=True)
    os.makedirs(FILES_DIR, exist_ok=True)
    readme = os.path.join(FILES_DIR, "readme.txt")
    if not os.path.exists(readme):
        with open(readme, "w", encoding="utf-8") as f:
            f.write("Catalogue de la boutique\n")
    conn = db()
    conn.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY,
            username TEXT UNIQUE NOT NULL,
            email TEXT NOT NULL,
            password_hash TEXT NOT NULL
        )
    """)
    accounts = [("alice", "alice@lab.local", seed_password("DEMO_PASSWORD")),
                ("bob", "bob@lab.local", seed_password("DEMO_PASSWORD"))]
    if os.environ.get("ADMIN_PASSWORD"):
        accounts.append(("admin", "admin@lab.local", os.environ["ADMIN_PASSWORD"]))
    for username, email, password in accounts:
        conn.execute("INSERT OR IGNORE INTO users VALUES (NULL,?,?,?)",
                     (username, email, auth.hash_password(password)))
    conn.commit()
    conn.close()


@app.after_request
def security_headers(response):
    response.headers["Content-Security-Policy"] = "default-src 'none'; frame-ancestors 'none'"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Cross-Origin-Resource-Policy"] = "same-origin"
    response.headers["Permissions-Policy"] = "geolocation=(), camera=(), microphone=()"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Cache-Control"] = "no-store"
    return response


@app.errorhandler(HTTPException)
def on_http_error(e):
    return jsonify({"error": e.name}), e.code


@app.errorhandler(Exception)
def on_error(e):
    # Le detail reste dans les journaux serveur, jamais dans la reponse HTTP
    log.error("Erreur non geree : %s", type(e).__name__, exc_info=e)
    return jsonify({"error": "internal error"}), 500


def require_admin():
    """Les routes /admin exigent l'en-tete X-Admin-Token egal au secret ADMIN_TOKEN."""
    provided = request.headers.get("X-Admin-Token", "")
    if not ADMIN_TOKEN or not hmac.compare_digest(provided, ADMIN_TOKEN):
        return jsonify({"error": "forbidden"}), 403
    return None


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "version": "1.0.0"})


@app.route("/users", methods=["GET"])
def list_users():
    conn = db()
    rows = conn.execute("SELECT id, username, email FROM users").fetchall()
    conn.close()
    return jsonify([{"id": r[0], "username": r[1], "email": r[2]} for r in rows])


@app.route("/user", methods=["GET"])
def get_user():
    username = request.args.get("username", "")
    conn = db()
    rows = conn.execute(
        "SELECT id, username, email FROM users WHERE username = ?", (username,)
    ).fetchall()
    conn.close()
    return jsonify([{"id": r[0], "username": r[1], "email": r[2]} for r in rows])


@app.route("/login", methods=["POST"])
def login():
    body = request.get_json(silent=True)
    if not isinstance(body, dict):
        body = {}
    username = str(body.get("username", ""))
    password = str(body.get("password", ""))
    conn = db()
    row = conn.execute(
        "SELECT id, username, password_hash FROM users WHERE username = ?", (username,)
    ).fetchone()
    conn.close()
    if row is None or not auth.check_password(password, row[2]):
        return jsonify({"error": "invalid credentials"}), 401
    token = auth.new_token()
    resp = make_response(jsonify({"token": token, "user": row[1]}))
    resp.set_cookie("session_id", token, secure=True, httponly=True, samesite="Lax")
    return resp


@app.route("/search", methods=["GET"])
def search():
    # Reponse JSON : la valeur n'est jamais interpretee comme du HTML par le navigateur
    q = request.args.get("q", "")
    return jsonify({"query": q, "results": []})


@app.route("/hello", methods=["GET"])
def hello():
    # Plus de template construit a partir de l'entree utilisateur (SSTI)
    name = request.args.get("name", "visiteur")
    return jsonify({"message": "Bonjour " + name})


def is_valid_hostname(value):
    if not value or len(value) > 253:
        return False
    for label in value.split("."):
        if not 1 <= len(label) <= 63 or label.startswith("-") or label.endswith("-"):
            return False
        if not set(label) <= HOSTNAME_CHARS:
            return False
    return True


def is_valid_host(value):
    try:
        ipaddress.ip_address(value)
        return True
    except ValueError:
        return is_valid_hostname(value)


@app.route("/api/ping", methods=["GET"])
def ping():
    host = request.args.get("host", "127.0.0.1")
    if not is_valid_host(host):
        return jsonify({"error": "invalid host"}), 400
    try:
        # Liste d'arguments, sans shell : l'hote ne peut pas etre interprete comme une commande
        out = subprocess.run([PING_BIN, "-c", "1", "-W", "2", "--", host],
                             capture_output=True, text=True, timeout=5, check=False)
    except subprocess.TimeoutExpired:
        return jsonify({"error": "timeout"}), 504
    except OSError:
        return jsonify({"error": "ping unavailable"}), 503
    return jsonify({"reachable": out.returncode == 0, "output": out.stdout})


@app.route("/download", methods=["GET"])
def download():
    name = request.args.get("file", "readme.txt")
    # send_from_directory refuse tout chemin qui sort de FILES_DIR (../, chemins absolus)
    return send_from_directory(FILES_DIR, name, as_attachment=True)


@app.route("/fetch", methods=["GET"])
def fetch():
    url = request.args.get("url", "")
    target = None
    for allowed in FETCH_ALLOWLIST:
        if url == allowed:
            target = allowed
    if target is None:
        return jsonify({"error": "url not allowed"}), 400
    try:
        r = requests.get(target, timeout=5, allow_redirects=False)
    except requests.RequestException:
        return jsonify({"error": "upstream unreachable"}), 502
    return jsonify({"status": r.status_code, "body": r.text[:2000]})


def imported_count(data):
    if not isinstance(data, (list, dict)):
        return None
    return len(data)


@app.route("/import", methods=["POST"])
def import_data():
    # JSON au lieu de pickle : aucune execution de code a la deserialisation
    try:
        data = json.loads(request.get_data(as_text=True) or "null")
    except ValueError:
        return jsonify({"error": ERR_BAD_REQUEST}), 400
    count = imported_count(data)
    if count is None:
        return jsonify({"error": ERR_BAD_REQUEST}), 400
    return jsonify({"imported": count})


@app.route("/import/yaml", methods=["POST"])
def import_yaml():
    try:
        data = yaml.safe_load(request.get_data(as_text=True))
    except yaml.YAMLError:
        return jsonify({"error": ERR_BAD_REQUEST}), 400
    count = imported_count(data or [])
    if count is None:
        return jsonify({"error": ERR_BAD_REQUEST}), 400
    return jsonify({"imported": count})


@app.route("/admin/users", methods=["GET"])
def admin_users():
    denied = require_admin()
    if denied:
        return denied
    conn = db()
    rows = conn.execute("SELECT id, username, email FROM users").fetchall()
    conn.close()
    return jsonify([{"id": r[0], "username": r[1], "email": r[2]} for r in rows])


@app.route("/admin/config", methods=["GET"])
def admin_config():
    denied = require_admin()
    if denied:
        return denied
    # Plus aucun secret expose : seulement la configuration non sensible
    return jsonify({"db_path": DB_PATH, "files_dir": FILES_DIR,
                    "fetch_allowlist": FETCH_ALLOWLIST, "debug": False})


@app.route("/openapi.json", methods=["GET"])
def openapi_spec():
    def q(name):
        return {"name": name, "in": "query", "schema": {"type": "string"}}

    ok = {"responses": {"200": {"description": "OK"}}}

    def body(schema):
        return {"requestBody": {"content": {"application/json": {"schema": schema}}},
                "responses": {"200": {"description": "OK"}}}

    spec = {
        "openapi": "3.0.0",
        "info": {"title": "app-devsecops", "version": "1.0.0"},
        "paths": {
            "/health": {"get": ok},
            "/users": {"get": ok},
            "/user": {"get": dict(ok, parameters=[q("username")])},
            "/login": {"post": body({"type": "object", "properties": {
                "username": {"type": "string"}, "password": {"type": "string"}}})},
            "/search": {"get": dict(ok, parameters=[q("q")])},
            "/hello": {"get": dict(ok, parameters=[q("name")])},
            "/api/ping": {"get": dict(ok, parameters=[q("host")])},
            "/download": {"get": dict(ok, parameters=[q("file")])},
            "/fetch": {"get": dict(ok, parameters=[q("url")])},
            "/admin/users": {"get": ok},
            "/admin/config": {"get": ok},
        },
    }
    return jsonify(spec)


init_db()

if __name__ == "__main__":
    app.run(host=HOST, port=PORT, debug=False)
