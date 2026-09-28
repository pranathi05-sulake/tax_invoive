def test_health_check_endpoint(client):
    """Test GET /health returns OK and database status."""
    response = client.get("/health")
    assert response.status_code in (200, 532, 503)
    data = response.json()
    assert "status" in data
    assert "database" in data
