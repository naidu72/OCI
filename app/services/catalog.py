from flask import jsonify, request

from common import NODE_NAME, create_app, db

app = create_app("catalog")


@app.get("/api/catalog/products")
def list_products():
    with db() as conn:
        rows = conn.execute("select id, name, price from products order by id").fetchall()
    return {"node": NODE_NAME, "products": rows}


@app.post("/api/catalog/products")
def create_product():
    body = request.get_json(silent=True) or {}
    if not body.get("name") or body.get("price") is None:
        return jsonify(error="name and price are required"), 400
    with db() as conn:
        row = conn.execute(
            "insert into products (name, price) values (%s, %s) returning id, name, price",
            (body["name"], body["price"]),
        ).fetchone()
    return jsonify(node=NODE_NAME, product=row), 201
