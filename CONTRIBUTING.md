# Contributing to DinoX

Thank you for your interest in contributing to DinoX! 🦖

## How to Contribute

### Reporting Bugs
- Check if the issue already exists in [GitHub Issues](https://github.com/rallep71/dinox/issues)
- Create a new issue with a clear description
- Include steps to reproduce, expected behavior, and actual behavior
- Add system information (distribution, DinoX version)

### Feature Requests
- Open a new issue with the "enhancement" label
- Describe the feature and why it would be useful
- If possible, include mockups or examples

### Code Contributions

1. **Fork the repository**
   ```bash
   git clone https://github.com/YOUR_USERNAME/dinox.git
   cd dinox
   ```

2. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Build and test**
   ```bash
   meson setup build
   ninja -C build
   ./build/main/dinox
   ```

4. **Commit your changes**
   - Use clear, descriptive commit messages
   - Reference issues if applicable: `Fix #123: Description`

5. **Submit a Pull Request**
   - Describe what your PR does
   - Link related issues
   - Add screenshots for UI changes

### Translations

DinoX uses gettext for translations. To contribute translations:

1. Check `main/po/` for existing language files
2. Update or create a `.po` file for your language
3. Test your translations locally
4. Submit a Pull Request

## Code Style

- Follow existing code conventions
- Use meaningful variable and function names
- Comment complex logic
- Keep functions focused and small

## Communication

- **XMPP Chat**: [dinox@chat.handwerker.jetzt](xmpp:dinox@chat.handwerker.jetzt?join)
- **Email**: dinox@handwerker.jetzt
- **GitHub Issues**: For bugs and feature requests

## License

By contributing, you agree that your contributions will be licensed under GPLv3.
