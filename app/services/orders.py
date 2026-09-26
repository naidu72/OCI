import psycopg
from flask import jsonify, request

from common import NODE_NAME, create_app, db

app = create_app("orders")


@app.get("/api/orders/")
def list_orders():
    with db() as conn:
        rows = conn.execute(
            """select o.id, o.quantity, o.created_at, p.name as product, p.price * o.quantity as total
               from orders o join products p on p.id = o.product_id
               order by o.id desc limit 50"""
        ).fetchall()
    return {"node": NODE_NAME, "orders": rows}


@app.post("/api/orders/")
def create_order():
    body = request.get_json(silent=True) or {}
    if not body.get("product_id"):
        return jsonify(error="product_id is required"), 400
    try:
        with db() as conn:
            row = conn.execute(
                "insert into orders (product_id, quantity) values (%s, %s) returning id, product_id, quantity, created_at",
                (body["product_id"], body.get("quantity", 1)),
            ).fetchone()
    except psycopg.errors.ForeignKeyViolation:
        return jsonify(error="unknown product_id"), 404
    return jsonify(node=NODE_NAME, order=row), 201
