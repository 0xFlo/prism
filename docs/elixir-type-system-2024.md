# Elixir Built-in Type System (v1.17-1.18)

**Last Updated**: 2025-10-11
**Elixir Version**: 1.17+ (Released June 2024), 1.18+ (Released December 2024)

---

## Overview

Elixir 1.17 and 1.18 introduced a **gradual, sound, set-theoretic type system** built directly into the compiler. This represents a fundamental shift from the old `@spec` annotation approach to automatic type inference and checking.

### Key Characteristics

1. **Gradual**: Uses `dynamic()` type for runtime checking where static analysis isn't possible
2. **Sound**: Inferred types align with actual program behavior
3. **Set-theoretic**: Supports unions, intersections, and negation of types
4. **Inference-based**: Does NOT require manual `@spec` annotations

---

## What Changed from `@spec`

### Old Approach (Pre-1.17)
```elixir
@spec add(integer(), integer()) :: integer()
def add(a, b) do
  a + b
end
```

**Problems:**
- ❌ Manual annotation burden
- ❌ Annotations could become stale/incorrect
- ❌ Only checked by external tools (Dialyzer)
- ❌ Not integrated into compiler

### New Approach (1.17+)
```elixir
def add(a, b) do
  a + b
end
```

**Benefits:**
- ✅ Automatic type inference
- ✅ Compiler checks types during compilation
- ✅ No manual annotations needed
- ✅ Always up-to-date with code
- ✅ Catches errors at compile-time

---

## What the Type System Catches

### 1. Incorrect Function Arguments (v1.18+)

```elixir
def drive(%User{}, car) do
  # Implementation
end

# Compiler warning:
User.drive({:ok, %User{}}, car_choices)
# ^ Expected %User{}, got {:ok, %User{}}
```

### 2. Unreachable Pattern Matches

```elixir
case value do
  :ok -> "success"
  {:error, _} -> "error"
  :ok -> "duplicate"  # ⚠️ Warning: unreachable
end
```

### 3. Invalid Tuple Access

```elixir
tuple = {:a, :b}
elem(tuple, 5)  # ⚠️ Warning: index out of bounds
```

### 4. Protocol Implementation Errors

```elixir
Enum.map(123, fn x -> x end)
# ⚠️ Warning: integer does not implement Enumerable protocol
```

---

## Supported Types (as of v1.18)

### Fully Supported
- ✅ Primitive types: `integer()`, `float()`, `binary()`
- ✅ Atoms and atom literals
- ✅ Maps (with field access checking)
- ✅ Tuples
- ✅ Lists
- ✅ Structs (with field validation)
- ✅ Pids, references, ports
- ✅ Function calls and returns

### Partial Support
- ⚠️ Guards (improving)
- ⚠️ Complex map types (improving)

### Not Yet Supported
- ❌ `for` comprehensions
- ❌ `with` expressions
- ❌ Closures (capturing variables)

---

## Practical Examples

### Example 1: Automatic Inference

```elixir
defmodule Calculator do
  def add(a, b) do
    a + b  # Compiler infers: integer() + integer() :: integer()
  end

  def calculate do
    add("5", "10")  # ⚠️ Warning: expected integer, got binary
  end
end
```

### Example 2: Map Field Access

```elixir
defmodule User do
  defstruct [:name, :age]

  def greet(user) do
    "Hello, #{user.name}"  # ✅ Compiler knows :name exists

    user.invalid_field     # ⚠️ Warning: field doesn't exist
  end
end
```

### Example 3: Protocol Checking

```elixir
defmodule MyData do
  def process(data) do
    Enum.map(data, & &1 * 2)
    # Compiler verifies data implements Enumerable
  end
end
```

---

## Migration Guide: From `@spec` to Built-in Types

### Should You Remove `@spec`?

**For most projects: No need to remove immediately**

The built-in type system works **alongside** `@spec`:
- `@spec` still provides documentation value
- External tools (ExDoc, Dialyzer) still use specs
- Specs can be more specific than inferred types

**However:**
- Don't rely on `@spec` for type safety
- Let the compiler do the type checking
- Consider specs as documentation, not enforcement

### When to Use `@spec` (Optional)

1. **Public API documentation** - Makes contracts explicit
2. **Complex return types** - When inference isn't specific enough
3. **Library development** - Helps library consumers

### When NOT to Use `@spec`

1. **Private functions** - Compiler infers automatically
2. **Simple functions** - Inference is sufficient
3. **Rapidly changing code** - Specs become maintenance burden

---

## Roadmap (Upcoming Features)

Based on Elixir core team plans:

1. **User-supplied type signatures** - Optional type annotations (NOT `@spec`)
2. **Improved guard typing** - Full type inference in guard clauses
3. **Better map/tuple typing** - More precise structural types
4. **Closure support** - Type checking for captured variables
5. **`for`/`with` support** - Full language coverage

---

## Best Practices for GSC Analytics

### ✅ DO

1. **Trust the compiler** - Let it infer types automatically
2. **Fix type warnings** - Treat them as bugs
3. **Write clear patterns** - Better patterns = better inference
4. **Use structs** - Compiler validates struct fields
5. **Keep functions simple** - Easier for type inference

### ❌ DON'T

1. **Don't add `@spec` everywhere** - Unnecessary with v1.17+
2. **Don't ignore type warnings** - They catch real bugs
3. **Don't use `String.to_atom/1` unsafely** - Type system can't help
4. **Don't mix types unsafely** - Use guards when needed

---

## Real-World Impact

### Before (Pre-1.17)
```elixir
# Bug went unnoticed until runtime
def calculate_stats(urls) do
  Enum.map(urls, fn url -> url.clicks end)
  # ^ Would crash if url was a tuple instead of map
end
```

### After (1.17+)
```elixir
# Compiler warning at build time:
def calculate_stats(urls) do
  Enum.map(urls, fn url -> url.clicks end)
  # ⚠️ Warning: url might be a tuple, which doesn't have :clicks field
end
```

---

## Further Reading

- [Elixir v1.17 Release Announcement](https://elixir-lang.org/blog/2024/06/12/elixir-v1-17-0-released/)
- [Elixir v1.18 Release Announcement](https://elixir-lang.org/blog/2024/12/19/elixir-v1-18-0-released/)
- [Elixir v1.18 Changelog](https://hexdocs.pm/elixir/1.18.0/changelog.html)
- [Elixir Streams: Type System Changes](https://www.elixirstreams.com/tips/elixir-118-type-system-changes)

---

**Summary**: Elixir's built-in type system (v1.17+) provides automatic type checking without manual annotations. For GSC Analytics, this means we can rely on compiler warnings for type safety instead of maintaining `@spec` annotations.
