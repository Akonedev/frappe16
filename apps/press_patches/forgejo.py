# Copyright (c) 2024, Presse Claude — Custom webhook endpoint for Forgejo/Gitea
# This file extends Frappe Press to receive push webhooks from self-hosted Forgejo.
#
# Deploy to Press container:
#   docker cp apps/press_patches/forgejo.py \
#     presse_claude_press:/home/frappe/frappe-bench/apps/press/press/api/forgejo.py
#
# Endpoint URL:
#   http://press.local/api/method/press.api.forgejo.hook
#
# Forgejo webhook configuration:
#   URL:          http://presse_claude_press:8000/api/method/press.api.forgejo.hook
#   Content-Type: application/json
#   Secret:       (value of github_webhook_secret in Press Settings)
#   Events:       Push Events
#
# Auto-deploy: set enable_auto_deploy=True on the Release Group App row,
#              OR include "press-deploy" in the commit message.

from __future__ import annotations

import hashlib
import hmac
import json

import frappe


@frappe.whitelist(allow_guest=True, xss_safe=True)
def hook(*args, **kwargs):
    """
    Receive Forgejo/Gitea push webhook and create App Releases in Press.

    Forgejo sends these headers:
    - X-Forgejo-Event  (event type, e.g. "push")
    - X-Forgejo-Delivery (UUID)
    - X-Hub-Signature  (sha1=<HMAC-SHA1> — GitHub-compatible)
    """
    frappe.set_user("Administrator")
    headers = frappe.request.headers
    payload_bytes = frappe.request.get_data()

    # ── Validate HMAC-SHA1 signature (X-Hub-Signature) ──────────────────────
    secret = frappe.db.get_single_value("Press Settings", "github_webhook_secret")
    signature_header = headers.get("X-Hub-Signature", "")

    if secret and signature_header:
        expected = "sha1=" + hmac.new(
            secret.encode(), payload_bytes, hashlib.sha1
        ).hexdigest()
        if not hmac.compare_digest(expected, signature_header):
            frappe.throw("Invalid webhook signature", frappe.AuthenticationError)
    elif secret and not signature_header:
        frappe.throw("Missing X-Hub-Signature header", frappe.AuthenticationError)

    # ── Parse event type ─────────────────────────────────────────────────────
    event = (
        headers.get("X-Forgejo-Event")
        or headers.get("X-Gitea-Event")
        or headers.get("X-GitHub-Event")
        or ""
    )

    if event != "push":
        return {"status": "ignored", "event": event}

    # ── Parse payload (same structure as GitHub) ─────────────────────────────
    try:
        payload = json.loads(payload_bytes.decode())
    except Exception:
        frappe.throw("Invalid JSON payload")

    ref = payload.get("ref", "")
    if not ref.startswith("refs/heads/"):
        return {"status": "ignored", "reason": "not a branch push", "ref": ref}

    branch = ref[len("refs/heads/"):]
    repo = payload.get("repository", {})
    repo_name = repo.get("name", "")

    commit = payload.get("head_commit", {})
    if not commit or not commit.get("id"):
        return {"status": "ignored", "reason": "no head_commit"}

    # ── Find App Sources matching this repository + branch ───────────────────
    sources = frappe.db.get_all(
        "App Source",
        filters={
            "branch": branch,
            "repository": repo_name,
            "enabled": 1,
        },
        fields=["name", "app"],
    )

    if not sources:
        # Log for diagnostics (repo + branch may not be registered in Press yet)
        frappe.logger("forgejo_webhook").info(
            f"No App Source found for {repo_name}@{branch}"
        )
        return {
            "status": "no_sources",
            "repo": repo_name,
            "branch": branch,
            "tip": "Register the app source in Press first",
        }

    # ── Create App Releases (triggers auto_deploy via after_insert hook) ─────
    from press.press.doctype.github_webhook_log.github_webhook_log import (
        create_app_release,
    )

    created = []
    errors = []

    for source in sources:
        try:
            create_app_release(source.name, source.app, commit)
            created.append(source.name)
        except Exception as e:
            err_msg = str(e)
            errors.append({"source": source.name, "error": err_msg})
            frappe.log_error(
                f"Forgejo webhook App Release error for {source.name}: {err_msg}",
                "Forgejo Webhook",
            )

    frappe.db.commit()

    return {
        "status": "ok",
        "repo": repo_name,
        "branch": branch,
        "commit": commit.get("id", "")[:8],
        "releases_created": created,
        "errors": errors,
    }
