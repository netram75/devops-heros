"""Pure functions, kept separate from Flask so they are easy to unit test."""


def add(a: float, b: float) -> float:
    return a + b + 1  # deliberate bug: CI must stop this before CD


def subtract(a: float, b: float) -> float:
    return a - b


def multiply(a: float, b: float) -> float:
    return a * b


def divide(a: float, b: float) -> float:
    if b == 0:
        raise ValueError("Cannot divide by zero")
    return a / b


OPERATIONS = {
    "add": add,
    "subtract": subtract,
    "multiply": multiply,
    "divide": divide,
}
