# Backend Fix: Mobile Login Password Check (`LoginAPIController`)

**File:** `app/Http/Controllers/Api/LoginAPIController.php`
**Endpoint:** `POST /api/check_login_api`
**Priority:** High (includes a security issue)

---

## 1. Problem

Employees can log in to the mobile app with the **master password**, but **not with their own password**.

### Cause

The password check is:

```php
if (!Hash::check($password, $employee->password) && $password !== $masterPassword) {
```

- The master password is compared as **plain text**, so it passes.
- The employee's password goes through `Hash::check()`, which only succeeds when the stored password is a **bcrypt hash** (a value starting with `$2y$`) of the password the user typed.

For the affected employees, the stored password isn't a bcrypt hash that matches. It is one of these:

1. **Plain text or MD5.** The web panel, an Excel import, or an older system saved it without `Hash::make()`.
2. **Hashed twice.** The code calls `Hash::make()` **and** `EmployeeModel` also hashes (a `'password' => 'hashed'` cast or a `setPasswordAttribute` mutator).
3. **Saved in a different place.** The web panel's change-password feature writes to a table or column that the mobile API doesn't read.

**Quick check:** look at the `password` value for one failing employee.

| Stored value looks like | Cause |
|---|---|
| The actual password, or 32 hex characters | Case 1 (plain text / MD5), fixed by section 3 |
| Starts with `$2y$`, 60 characters, but the correct password fails | Case 2 or 3, see section 5 |

---

## 2. ⚠️ Security issue: login without a password

```php
$masterPassword = config('app.master_password');
...
&& $password !== $masterPassword
```

If `master_password` is **not set** in `.env` or `config/app.php`, `$masterPassword` is `null`.
If a request **leaves out the `password` field**, `$password` is also `null`.

`null !== null` is `false`, so the password check passes. **Anyone who knows an employee code can log in with no password.**

Reproduce it in Postman: `POST /api/check_login_api` with only `emp_code` in the body.

---

## 3. Fix

### 3.1 Replace the password check in `checkLoginAPI()`

**Remove:**

```php
// Password check (hash + master password)
if (!Hash::check($password, $employee->password) && $password !== $masterPassword) {
    $this->logLoginAttempt($req, $emp_code, $employee->id, 'failed_password');
    return response()->json([
        'status'  => false,
        'message' => 'Invalid credentials.'
    ], 401);
}
```

**Replace with:**

```php
// Password check: employee's own password first, master password as fallback
if (!is_string($password) || $password === '') {
    $this->logLoginAttempt($req, $emp_code, $employee->id, 'failed_password');
    return response()->json([
        'status'  => false,
        'message' => 'Invalid credentials.'
    ], 401);
}

$userOk   = $this->verifyEmployeePassword($employee, $password);
$masterOk = !$userOk
    && is_string($masterPassword) && $masterPassword !== ''
    && hash_equals($masterPassword, $password);

if (!$userOk && !$masterOk) {
    $this->logLoginAttempt($req, $emp_code, $employee->id, 'failed_password');
    return response()->json([
        'status'  => false,
        'message' => 'Invalid credentials.'
    ], 401);
}
```

### 3.2 Add this private method to the controller (next to `logLoginAttempt`)

```php
/**
 * Checks the employee's own password. Accepts bcrypt/argon hashes, and also
 * legacy plain-text or MD5 values — those are upgraded to bcrypt on the
 * first successful login so they stop being stored insecurely.
 */
private function verifyEmployeePassword($employee, string $password): bool
{
    $stored = (string) $employee->password;
    if ($stored === '') {
        return false;
    }

    // Proper hash ($2y$..., argon) — normal path.
    if (password_get_info($stored)['algo'] !== null) {
        return Hash::check($password, $stored);
    }

    // Legacy: plain text or MD5.
    $legacyOk = hash_equals($stored, $password)
        || hash_equals(strtolower($stored), md5($password));

    if ($legacyOk) {
        // toBase() skips model casts/mutators, so this can't double-hash.
        EmployeeModel::whereKey($employee->id)->toBase()
            ->update(['password' => Hash::make($password)]);
        $employee->password = Hash::make($password);
    }

    return $legacyOk;
}
```

**Notes:**
- The method checks the stored format **before** calling `Hash::check()`. On Laravel 10 and later, `Hash::check()` can throw an error on a value that isn't bcrypt, instead of returning `false`.
- Plain-text and MD5 passwords are replaced with a bcrypt hash on the first successful login, so they stop being stored insecurely.
- The existing force-reset check (`Hash::check('admin', ...)` → 423) still works, because it runs on the upgraded hash.

---

## 4. Fix where passwords are saved (otherwise the problem comes back)

Section 3 only repairs passwords as users log in. **Every place that creates or changes an employee password** must save a bcrypt hash, **exactly once**:

- Add employee (web panel)
- Change password / reset password
- Excel / bulk import
- Any seeders or scripts

Rule:
- If `EmployeeModel` has `'password' => 'hashed'` in `$casts`, or a `setPasswordAttribute()` mutator, assign the **plain** password and **don't** call `Hash::make()`.
- Otherwise, save `Hash::make($password)`.

---

## 5. Case that can't be fixed automatically: double hashing

If the stored value starts with `$2y$` but the correct password still fails, the password was hashed twice. Hashes can't be reversed, so:

1. Remove the double hashing (section 4).
2. Reset those employees' passwords, for example to `admin`, so they go through the existing "Please change your password" (423) flow.

---

## 6. Recommended cleanup (same file)

| Item | Why |
|---|---|
| Add `$req->validate(['emp_code' => 'required', 'password' => 'required\|string']);` at the start of `checkLoginAPI` | Rejects empty requests early |
| Record when the master password was used, e.g. a `'success_master'` status in `logLoginAttempt` | Shows when someone logged in with the master password |
| Load only `companyDetails.department` and `companyDetails.designation` | `salaryDetails`, `statutoryDetails` and `managerDetails` are loaded but never used, which slows down login |
| Make sure the `emp_code` column has a database index | `whereHas` searches it on every login |
| Remove the `if ($employee->delete == 1)` block | It can never run, because the query already filters `where('delete', 0)` |
| Remove unused imports (PHPMailer, PDF, most models) | Clutter |

---

## 7. Deploy

```bash
php artisan config:clear
php artisan route:clear
```

Make sure `MASTER_PASSWORD` is set in `.env` if a master password is still needed.

---

## 8. Test checklist

- [ ] Employee with a **plain-text or MD5** password logs in with their own password → **200**. Their `password` column now starts with `$2y$`.
- [ ] The same employee logs in again → **200**.
- [ ] Employee with a **bcrypt** password logs in with their own password → **200**.
- [ ] Wrong password → **401**.
- [ ] Request with **only `emp_code`** (no password) → **401**. Before this fix, this logged in.
- [ ] Master password → **200**.
- [ ] Employee whose password is `admin` → **423** with `force_reset: true`.
- [ ] Employee with `mobile_login != 'Yes'` → **403**.

---

## 9. Related issue: Pre-Recruitment API returns 403 for HO HR

The mobile app shows Pre-Recruitment to every role **except** `staff` and `employee`, which includes **HO HR**. But `GET /api/pre-recruitment/candidates` returns:

```json
{ "status": false, "message": "Access denied" }
```

That message comes from the role or permission check inside `PreRecruitmentApiController`. Please:

1. Find where it returns "Access denied" and add HO HR to the allowed roles. The mobile app accepts the role name `HO HR`, `ho-hr` or `hohr`, so use the spelling stored in `companyDetails.role`.
2. Keep the rule the same as the app: allow every role except staff and employee, or tell the mobile team which roles are allowed so the app can match.

Both routes (`/pre-recruitment/candidates` and `/pre-recruitment/submit-details`) check only `auth:sanctum` in `routes/api.php`, so the controller's own check is the only role check.
