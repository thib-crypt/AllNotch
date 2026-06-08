# Contributing to AllNotch

Thank you for your interest in contributing to AllNotch! We welcome contributions from everyone — developers, designers, testers, and documentation writers.

## Table of Contents

- [How to Contribute](#how-to-contribute)
- [Code of Conduct](#code-of-conduct)
- [Development Setup](#development-setup)
- [Pull Request Process](#pull-request-process)
- [Coding Guidelines](#coding-guidelines)
- [Design Contributions](#design-contributions)
- [Documentation](#documentation)

---

## How to Contribute

1. **Fork the repository** and clone your fork locally.
2. **Create a feature branch**: `git switch -c feature/your-feature-name`
3. **Make your changes** following the guidelines below.
4. **Test your changes** — ensure they build and don't break existing functionality.
5. **Commit** with clear, descriptive messages.
6. **Push** to your fork and submit a **pull request** against `main`.
7. **Participate in code review** and address feedback.

## Code of Conduct

We are committed to fostering a welcoming and inclusive environment. Please read our [Code of Conduct](CODE_OF_CONDUCT.md) before participating.

## Development Setup

**Requirements:**
- macOS 14.6 or later (macOS 15 recommended)
- Xcode 15.0+ with Swift 5.9 toolchain
- A MacBook with a notch (for full-feature testing)

**Clone and build:**
```bash
git clone https://github.com/thib-crypt/AllNotch.git
cd AllNotch
open AllNotch.xcodeproj
# Select your Mac as destination, then ⌘R
```

Swift Package dependencies resolve automatically on first build.

## Pull Request Process

- Keep your branch up to date with `main` before submitting.
- Provide a clear description of your changes and the motivation behind them.
- Reference any related issues.
- Add screenshots or screen recordings for UI changes.
- Ensure the project builds without errors.
- Respond to review feedback promptly.

## Coding Guidelines

- Follow [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- Use meaningful variable and function names.
- Keep functions focused and concise.
- Add inline documentation for public APIs and complex logic.
- Avoid introducing unnecessary dependencies.

## Plugin Architecture

New features should be implemented as plugins when possible. Each plugin is a struct conforming to `NotchPlugin` registered in `allPlugins`. See the existing Screenshot plugin as a reference.

## Design Contributions

- Submit UI/UX improvements, mockups, or visual assets.
- Maintain consistency with macOS Human Interface Guidelines.
- Provide rationale for design decisions.

## Documentation

- Improve user guides and setup instructions.
- Clarify build steps and usage examples.
- Keep the README and CONTRIBUTING in sync with the codebase.

---

Thank you for helping make AllNotch better!
