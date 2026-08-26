from consumer_app import hello


def test_hello() -> None:
    assert hello() == "Hello from consumer-app!"
