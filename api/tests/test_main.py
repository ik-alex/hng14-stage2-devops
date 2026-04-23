"""Unit tests for the FastAPI job API.

Redis is mocked so these tests run without a real Redis instance.
"""
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient


# Patch redis.Redis BEFORE importing main, so the module-level
# `r = redis.Redis(...)` call gets a mock instead of a real client.
with patch("redis.Redis") as mock_redis_class:
    mock_redis_instance = MagicMock()
    mock_redis_class.return_value = mock_redis_instance
    from main import app, r

client = TestClient(app)


def test_create_job_returns_job_id():
    """POST /jobs should return a job_id and call Redis to queue the job."""
    # Reset mocks for this test
    r.lpush = MagicMock()
    r.hset = MagicMock()

    response = client.post("/jobs")

    assert response.status_code == 200
    data = response.json()
    assert "job_id" in data
    assert len(data["job_id"]) == 36  # UUID4 string length

    # Verify Redis was called correctly
    r.lpush.assert_called_once()
    r.hset.assert_called_once()


def test_get_job_returns_status_when_exists():
    """GET /jobs/{id} should return the status when the job exists in Redis."""
    # Mock Redis to return bytes "completed" (matches real Redis behavior)
    r.hget = MagicMock(return_value=b"completed")

    response = client.get("/jobs/test-job-123")

    assert response.status_code == 200
    assert response.json() == {"job_id": "test-job-123", "status": "completed"}
    r.hget.assert_called_once_with("job:test-job-123", "status")


def test_get_job_returns_404_when_not_found():
    """GET /jobs/{id} should return 404 when Redis has no record of the job."""
    # Mock Redis to return None (no such job)
    r.hget = MagicMock(return_value=None)

    response = client.get("/jobs/nonexistent-id")

    assert response.status_code == 404
    assert response.json() == {"detail": "not found"}
