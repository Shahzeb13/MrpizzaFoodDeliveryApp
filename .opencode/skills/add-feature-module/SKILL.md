---
name: add-feature-module
description: Scaffold a new feature module for MrPizza (feature-first Flutter structure). Trigger on "add a feature", "new module", "create a screen area for X".
---

# Add Feature Module — MrPizza

Create `lib/features/<feature_name>/` with:
```
data/<feature_name>_repository.dart   # Supabase calls only, named fetchX/createX/updateX
models/<feature_name>_model.dart      # data class, fromJson/toJson if it maps to a table
providers/<feature_name>_provider.dart # exposes state (loading/data/error) to UI
screens/<feature_name>_screen.dart    # <FeatureName>Screen widget
```

Rules:
- Screens never call Supabase directly — always through the repository.
- Reuse the existing role-guard pattern (see `features/rider/`) if the feature needs access control — don't invent a new one.
- Register the new screen wherever routing lives (`lib/app/`).
- If it implies a new Supabase table, flag that instead of assuming it exists.