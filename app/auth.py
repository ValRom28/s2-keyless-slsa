"""Authentification et appel a l'annuaire interne.

Aucun secret dans le code : tout vient de l'environnement (secrets Gitea /
variables du conteneur).
"""
import os
import secrets

import requests
from werkzeug.security import check_password_hash, generate_password_hash

API_URL = os.environ.get("API_URL", "https://annuaire.recette.lab/api/users")
API_USER = os.environ.get("API_USER", "")
API_PASSWORD = os.environ.get("API_PASSWORD", "")

# Cle de signature des sessions : fournie par l'environnement, sinon aleatoire
# (les sessions sont alors invalidees a chaque redemarrage, ce qui est sans
# consequence en recette).
SECRET_KEY = os.environ.get("SECRET_KEY") or secrets.token_hex(32)


def hash_password(password):
    """Hachage sale et lent (scrypt via Werkzeug), adapte aux mots de passe."""
    return generate_password_hash(password)


def check_password(password, stored_hash):
    return check_password_hash(stored_hash, password)


def new_token():
    """Jeton de session issu d'un generateur cryptographique."""
    return secrets.token_urlsafe(32)


def sync_users():
    response = requests.get(API_URL, auth=(API_USER, API_PASSWORD), timeout=5)
    response.raise_for_status()
    return response.json()
