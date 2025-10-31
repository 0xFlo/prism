# Elixir Guidelines

## Coding Patterns
- **Pattern Matching**: Use pattern matching in function heads for control flow
- **Railway-Oriented Programming**: Chain operations with `with` for elegant error handling
  ```elixir
  with {:ok, user} <- find_user(id),
       {:ok, updated} <- update_user(user, attrs) do
    {:ok, updated}
  end
  ```
### **Result Tuples**: Return tagged tuples `{:ok, result}` or `{:error, reason}` for operations that can fail:
- Use specific error atoms when helpful: `{:error, :not_found}`, `{:error, :timeout}`
- Compose with `with` for elegant error propagation
- Avoid exceptions for expected failure cases

## Data Validation Patterns
- **Ecto.Changeset**: Consider Ecto.Changeset for complex validation at boundaries (APIs, file parsing) when you need structured error handling
- **Guard Clauses**: Use guards for simple type and format validation at function boundaries
- **Early Returns**: Fail fast with clear error messages for invalid inputs
- **Domain Validators**: Create dedicated validation modules for complex business rules

