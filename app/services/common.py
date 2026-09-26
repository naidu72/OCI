import os
import socket

import psycopg
from flask import Flask, jsonify
from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row

NODE_NAME = os.environ.get("NODE_NAME", socket.gethostname())

# Both database nodes are listed; libpq tries them in order and only accepts the one
# that is writable, so the services follow the primary after a failover.
_hosts = os.environ["DB_HOSTS"].split(",")
CONNINFO = make_conninfo(
    host=",".join(_hosts),
    port=",".join(["5432"] * len(_hosts)),
    dbname=os.environ.get("DB_NAME", "appdb"),
    user=os.environ.get("DB_USER", "app"),
    password=os.environ["DB_PASSWORD"],
    target_session_attrs="read-write",
    connect_timeout=3,
)


def db():
    return psycopg.connect(CONNINFO, row_factory=dict_row)


def create_app(name):
    app = Flask(name)

    @app.get("/live")
    def live():
        return {"status": "ok", "service": name, "node": NODE_NAME}

    @app.get(f"/api/{name}/health")
    def health():
        try:
            with db() as conn:
                row = conn.execute(
                    "select current_setting('cluster_name') as db_node, pg_is_in_recovery() as standby"
                ).fetchone()
            return {"status": "ok", "service": name, "node": NODE_NAME, "db": row}
        except psycopg.Error as e:
            return jsonify(status="db-unavailable", service=name, node=NODE_NAME, error=str(e)), 503

    @app.errorhandler(psycopg.OperationalError)
    def db_down(e):
        return jsonify(error="database unavailable", node=NODE_NAME), 503

    return app
