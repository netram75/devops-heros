import pytest

from app.main import create_app


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("APP_VERSION", "test-sha")
    monkeypatch.delenv("API_TOKEN", raising=False)
    return create_app().test_client()


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}


def test_index_reports_version_and_no_token(client):
    body = client.get("/").get_json()
    assert body["service"] == "session16-calculator"
    assert body["version"] == "test-sha"
    assert body["api_token_configured"] is False


def test_index_reports_token_without_leaking_it(client, monkeypatch):
    monkeypatch.setenv("API_TOKEN", "not-a-real-token")
    resp = client.get("/")
    assert resp.get_json()["api_token_configured"] is True
    assert b"not-a-real-token" not in resp.data


@pytest.mark.parametrize(
    ("op", "a", "b", "expected"),
    [("add", 2, 3, 5), ("subtract", 9, 4, 5), ("multiply", 6, 7, 42), ("divide", 9, 2, 4.5)],
)
def test_operations(client, op, a, b, expected):
    resp = client.get(f"/api/{op}?a={a}&b={b}")
    assert resp.status_code == 200
    assert resp.get_json()["result"] == expected


def test_divide_by_zero_is_400(client):
    resp = client.get("/api/divide?a=1&b=0")
    assert resp.status_code == 400
    assert "zero" in resp.get_json()["error"]


def test_unknown_operation_is_404(client):
    assert client.get("/api/power?a=2&b=3").status_code == 404


def test_missing_or_bad_numbers_is_400(client):
    assert client.get("/api/add?a=2").status_code == 400
    assert client.get("/api/add?a=two&b=3").status_code == 400
