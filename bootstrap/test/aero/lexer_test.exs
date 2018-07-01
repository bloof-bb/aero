defmodule Aero.LexerTest do
  use ExUnit.Case

  test "whitespace is classified as newlines and spaces" do
    source = "\r\n  t_1 t_2 \r t_3 \nt_4\r\nt_5 \n \n t_6 "

    {:ok, tokens, 6} = Aero.Lexer.tokenize source

    assert tokens === [
      {:newline, 1},
      {:snake_case, 2, :t_1},
      {:space, 2},
      {:snake_case, 2, :t_2},
      {:space, 2},
      {:snake_case, 2, :t_3},
      {:newline, 2},
      {:snake_case, 3, :t_4},
      {:newline, 3},
      {:snake_case, 4, :t_5},
      {:newline, 4},
      {:snake_case, 6, :t_6},
      {:space, 6}
    ]
  end

  test "newlines are tokenized after comments" do
    source = "-- comment\nt_1-- comment "

    {:ok, tokens, 2} = Aero.Lexer.tokenize source

    assert tokens === [
      {:newline, 1},
      {:snake_case, 2, :t_1}
    ]
  end

  test "basic string" do
    source = "\"test\""

    {:ok, tokens, 1} = Aero.Lexer.tokenize source

    assert tokens === [
      {:string_lit, 1, "test"}
    ]
  end

  test "basic char" do
    source = "'a'"

    {:ok, tokens, 1} = Aero.Lexer.tokenize source

    assert tokens === [
      {:char_lit, 1, ?a}
    ]
  end

  test "identifiers are separated by their case" do
    source = "test Test __TEST__ test_1 Test1 __TEST_1__"

    {:ok, tokens, 1} = Aero.Lexer.tokenize source

    assert tokens === [
      {:snake_case, 1, :test},
      {:space, 1},
      {:title_case, 1, :Test},
      {:space, 1},
      {:special, 1, :__TEST__},
      {:space, 1},
      {:snake_case, 1, :test_1},
      {:space, 1},
      {:title_case, 1, :Test1},
      {:space, 1},
      {:special, 1, :__TEST_1__}
    ]
  end
end
