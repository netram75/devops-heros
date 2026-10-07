import pytest

from app.main import MAX_TITLE_LEN, create_app


@pytest.fixture()
def client():
    app = create_app()
    app.config.update(TESTING=True)
    return app.test_client()


def test_index_reports_version_and_commit(client, monkeypatch):
    monkeypatch.setenv("APP_VERSION", "1.2.3")
    monkeypatch.setenv("GIT_SHA", "abc123")
    res = client.get("/")
    assert res.status_code == 200
    body = res.get_json()
    assert body["service"] == "release-checklist"
    assert body["version"] == "1.2.3"
    assert body["commit"] == "abc123"


def test_health_and_ready(client):
    assert client.get("/healthz").get_json() == {"status": "ok"}
    assert client.get("/readyz").get_json() == {"status": "ready"}


def test_list_starts_empty(client):
    res = client.get("/api/items")
    assert res.status_code == 200
    assert res.get_json() == {"items": [], "count": 0}


def test_add_and_get_item(client):
    res = client.post("/api/items", json={"title": "  scan the image  "})
    assert res.status_code == 201
    item = res.get_json()
    assert item == {"id": 1, "title": "scan the image", "done": False}
    assert client.get("/api/items/1").get_json() == item
    assert client.get("/api/items").get_json()["count"] == 1


def test_ids_increase(client):
    first = client.post("/api/items", json={"title": "a"}).get_json()
    second = client.post("/api/items", json={"title": "b"}).get_json()
    assert second["id"] == first["id"] + 1


@pytest.mark.parametrize(
    "payload",
    [None, [], {"title": ""}, {"title": "   "}, {"title": 42}, {"name": "x"}],
)
def test_add_rejects_bad_input(client, payload):
    if payload is None:
        res = client.post("/api/items", data="not json", content_type="text/plain")
    else:
        res = client.post("/api/items", json=payload)
    assert res.status_code == 400
    assert "error" in res.get_json()


def test_add_rejects_too_long_title(client):
    res = client.post("/api/items", json={"title": "x" * (MAX_TITLE_LEN + 1)})
    assert res.status_code == 400


def test_mark_done(client):
    client.post("/api/items", json={"title": "push to ghcr"})
    res = client.post("/api/items/1/done")
    assert res.status_code == 200
    assert res.get_json()["done"] is True


def test_unknown_item_is_404_json(client):
    for res in (client.get("/api/items/99"), client.post("/api/items/99/done")):
        assert res.status_code == 404
        assert res.get_json() == {"error": "not found"}


def test_each_app_has_its_own_store():
    a = create_app().test_client()
    b = create_app().test_client()
    a.post("/api/items", json={"title": "only in a"})
    assert b.get("/api/items").get_json()["count"] == 0
