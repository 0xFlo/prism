# Test Writing Guidelines

**CRITICAL: Never assert on internal state or implementation details.**
Instead, Test at the highest level that makes sense:

- Controller test > Service test > Unit test
- One integration test can replace 10 unit tests
- Only unit test complex algorithms that are hard to test through the API

## Semantic Test Coverage

You are an LLM, Use your understanding of language to ensure tests cover what matters:

- Map each test to a business requirement
- Identify missing scenarios from the requirements
- Consolidate tests that verify the same business behavior

## Core Philosophy

- **Test behavior, not implementation**: Focus on what the code does, not how it does it
- **Test at the highest level practical**: Prefer integration tests over unit tests when reasonable
- **Don't test trivial code**: Skip tests for simple functions you can write correctly in one shot
- **Tests should survive refactoring**: Good tests break when behavior changes, not when implementation changes

## Write tests that survive refactoring

- Assert ONLY on observable behavior (API responses, user-visible output, database changes)
- If changing HOW the code works would break your test, you're testing wrong

## Writing Resilient Tests

1. **Assert on outputs/side effects**: What the user sees or what gets saved to the database
2. **Use minimal assertions**: Only assert what's essential to the test's purpose
3. **Avoid testing intermediate state**: Focus on final outcomes
4. **Make tests independent**: Each test should set up its own state and clean up after itself
5. **Use descriptive test names**: "should calculate tax correctly for international orders" not "test_calculate_tax_2"

## Requirements-Driven Testing

Before writing tests, analyze what the system is supposed to do:

1. **Read the user story/requirement** (from comments, docs, or code context)
2. **Identify the business behaviors** that need protection
3. **Write tests that verify those behaviors**, not the current implementation

### Example:

```javascript
// If you see this comment or requirement:
// "Users can only apply for jobs after email confirmation"

// Generate tests that verify the BUSINESS RULE:
test("unconfirmed users cannot apply for jobs");
test("confirmed users can apply for jobs");
test("confirmation email triggers pending applications");

// NOT tests of HOW it's implemented:
test("user.confirmed_at is not null"); // ❌ Implementation detail
```

## What TO Test

1. **Complex state transformations**: When logic is too complicated to write confidently once
2. **API boundaries/cut points**: The public interface of modules/services
3. **Business requirements**: Test that actual business rules are enforced
4. **User journeys**: Complete workflows from the user's perspective that must not break
5. **Edge cases that matter**: Only test boundaries that represent real scenarios

## What NOT TO Test

1. **Simple getters/setters**: Unless they contain logic
2. **Internal helper functions**: Test them through the public API instead
3. **Implementation details**: Don't assert on internal state, private methods, or data structures
4. **Every possible input**: Focus on representative cases and real edge cases
5. **Simple CRUD**: Unless there are business rules involved

## Example

```javascript
// ❌ BAD - breaks when implementation changes
expect(service._users.length).toBe(1);
expect(token.context).toBe("session");
expect(cache._internal.size).toBe(5);

// ✅ GOOD - tests behavior, not implementation
expect(api.post("/login", credentials)).toReturn(200);
expect(database.users.count()).toBe(1);
expect(page.text()).toContain("Welcome");
```
