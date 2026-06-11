# Terminal UI Components & Animations

This document provides a visual reference and implementation guide for the terminal animations and interactive assets available within the core toolset. 

Creating a great Developer Experience (DX) in the command line requires responsive, intuitive, and visually clear feedback. The components demonstrated below are designed to handle user input and background processes gracefully without cluttering the terminal output.

---

### 1. Interactive Selection Menu
**File:** `simple_list.gif`

![Interactive List](./assets/simple_list.gif)

**Visual Behavior:**
Generates a clean, inline selectable menu directly in the standard output. The currently focused item is visually highlighted, and users can navigate up and down using standard keyboard arrow keys. Once a selection is made by pressing `Enter`, the prompt resolves and the terminal cursor returns to normal.

**Technical Context & Ideal Use Cases:**
* **Interactive CLI Wizards:** Perfect for scaffolding new projects where a user needs to pick a framework, language, or starter template.
* **Configuration Scripts:** Useful for setup scripts that require users to choose between discrete options (e.g., selecting a package manager like npm, yarn, or pnpm).
* **Action Routing:** Allows users to choose an execution path in a multi-tool CLI without needing to memorize complex command-line flags.

---

### 2. Determinate Progress Bar
**File:** `progress.gif`

![Progress Bar](./assets/progress.gif)

**Visual Behavior:**
Renders a smooth, dynamic, and colorful horizontal progress track. It includes real-time percentage updates and a customizable status message above the bar (e.g., "Downloading fern..."). The animation updates cleanly in place, avoiding the common issue of printing a new line for every percentage tick.

**Technical Context & Ideal Use Cases:**
* **Large File Operations:** Best utilized when the total size or duration of an operation is known ahead of time, such as chunked file downloads or large asset copying.
* **Build & Compilation Steps:** Excellent for providing feedback during multi-step build processes, helping the user understand exactly how far along the compiler is.
* **Batch Processing:** Useful when iterating over large datasets or performing multiple sequential API calls where the total number of operations is fixed.

---

### 3. Indeterminate Loading Spinner
**File:** `spinner.gif`

![Loading Spinner](./assets/spinner.gif)

**Visual Behavior:**
A minimalist, non-blocking text animation that cycles through characters to create a spinning effect. It sits inline with a descriptive status message (e.g., "Loading forever...") and indicates that a background process is active and healthy, even if the exact completion time is unknown.

**Technical Context & Ideal Use Cases:**
* **Network Requests:** The standard choice for awaiting API responses, establishing database connections, or pinging external servers.
* **Environment Setup:** Ideal for backend processes like resolving dependencies or calculating local environment variables where exact progress calculation is impossible.
* **Unobtrusive Processing:** Best for quick tasks where a full progress bar would be visual overkill, keeping the terminal aesthetic clean and focused.