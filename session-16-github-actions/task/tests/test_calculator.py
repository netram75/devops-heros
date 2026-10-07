import pytest

from app.calculator import OPERATIONS, add, divide, multiply, subtract


def test_add():
    assert add(10, 5) == 15


def test_subtract():
    assert subtract(10, 5) == 5


def test_multiply():
    assert multiply(10, 5) == 50


def test_divide():
    assert divide(10, 4) == 2.5


def test_divide_by_zero():
    with pytest.raises(ValueError, match="Cannot divide by zero"):
        divide(10, 0)


def test_operations_table_has_all_four():
    assert sorted(OPERATIONS) == ["add", "divide", "multiply", "subtract"]
