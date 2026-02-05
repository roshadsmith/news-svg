import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/news_category.dart';
import '../models/source_config.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late TextEditingController _proxyController;
  late TextEditingController _updateController;

  @override
  void initState() {
    super.initState();
    _proxyController = TextEditingController(
      text: widget.controller.settings.proxyUrl,
    );
    _updateController = TextEditingController(
      text: widget.controller.settings.updateUrl,
    );
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.settings.proxyUrl !=
        widget.controller.settings.proxyUrl) {
      _proxyController.text = widget.controller.settings.proxyUrl;
    }
    if (oldWidget.controller.settings.updateUrl !=
        widget.controller.settings.updateUrl) {
      _updateController.text = widget.controller.settings.updateUrl;
    }
  }

  @override
  void dispose() {
    _proxyController.dispose();
    _updateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sources = widget.controller.settings.sources;

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: theme.brightness == Brightness.dark
                  ? const [Color(0xFF101417), Color(0xFF141B20)]
                  : const [Color(0xFFF7F3EE), Color(0xFFF1F6F8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Settings',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                        fontFamily: 'Georgia',
                        fontFamilyFallback: const ['Times New Roman', 'serif'],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage sources and app preferences.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    _SectionCard(
                      title: 'Appearance',
                      subtitle: 'Theme and text size preferences.',
                      child: _AppearanceSettings(
                        themeMode: widget.controller.settings.themeMode,
                        textScale: widget.controller.settings.textScale,
                        onThemeModeChanged: widget.controller.updateThemeMode,
                        onTextScaleChanged: widget.controller.updateTextScale,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SectionCard(
                      title: 'Advanced',
                      subtitle: 'Proxy + update configuration for testing.',
                      child: Column(
                        children: [
                          TextField(
                            controller: _proxyController,
                            decoration: const InputDecoration(
                              hintText: 'http://localhost:4000',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _updateController,
                            decoration: const InputDecoration(
                              hintText: 'https://example.com/version.json',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                              onPressed: () => _saveAdvanced(context),
                              child: const Text('Save'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Sources',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _addSource(context),
                          icon: const Icon(Icons.add),
                          label: const Text('Add source'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (sources.isEmpty)
                      Text(
                        'No sources yet. Add one to get started.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      )
                    else
                      ...sources.map((source) {
                        return _SourceTile(
                          source: source,
                          onToggle: (enabled) => widget.controller.toggleSource(
                            source.id,
                            enabled,
                          ),
                          onCategoryChanged: (category) => widget.controller
                              .updateSourceCategory(source.id, category),
                          onRemove: () => _confirmRemove(context, source),
                        );
                      }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _addSource(BuildContext context) async {
    final result = await showModalBottomSheet<_SourceDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const _AddSourceSheet(),
    );

    if (result == null) return;

    await widget.controller.addSource(
      name: result.name,
      listUrl: result.listUrl,
      baseUrl: Uri.tryParse(result.listUrl)?.origin ?? result.listUrl,
      articleUrlPattern: null,
      category: result.category,
      enabled: result.enabled,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Added ${result.name}.')));
    }
  }

  Future<void> _confirmRemove(BuildContext context, SourceConfig source) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove source?'),
          content: Text('Remove ${source.name} from your list?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (remove == true) {
      await widget.controller.removeSource(source.id);
    }
  }

  void _saveAdvanced(BuildContext context) {
    final proxyValue = _proxyController.text.trim();
    final updateValue = _updateController.text.trim();

    if (!_isValidUrl(proxyValue)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid http(s) proxy URL.')),
      );
      return;
    }

    if (updateValue.isNotEmpty && !_isValidUrl(updateValue)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid http(s) update URL.')),
      );
      return;
    }

    widget.controller.updateProxyUrl(proxyValue);
    widget.controller.updateUpdateUrl(updateValue);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Advanced settings updated.')));
  }

  bool _isValidUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    return (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.onToggle,
    required this.onCategoryChanged,
    required this.onRemove,
  });

  final SourceConfig source;
  final ValueChanged<bool> onToggle;
  final ValueChanged<NewsCategory> onCategoryChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final host =
        Uri.tryParse(source.listUrl)?.host.replaceFirst('www.', '') ??
        source.listUrl;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  host,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _CompactCategoryMenu(
            value: source.category,
            onChanged: onCategoryChanged,
          ),
          const SizedBox(width: 4),
          Switch(value: source.enabled, onChanged: onToggle),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline),
            color: theme.colorScheme.error,
            tooltip: 'Remove source',
          ),
        ],
      ),
    );
  }
}

class _AddSourceSheet extends StatefulWidget {
  const _AddSourceSheet();

  @override
  State<_AddSourceSheet> createState() => _AddSourceSheetState();
}

class _AddSourceSheetState extends State<_AddSourceSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _listUrlController = TextEditingController();
  bool _enabled = true;
  NewsCategory _category = NewsCategory.local;

  @override
  void dispose() {
    _nameController.dispose();
    _listUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add source',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Enter a name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _listUrlController,
              decoration: const InputDecoration(labelText: 'List URL'),
              validator: (value) =>
                  _isValidUrl(value) ? null : 'Enter a valid URL',
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable immediately'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            const SizedBox(height: 8),
            _CategoryPicker(
              value: _category,
              onChanged: (value) => setState(() => _category = value),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton(onPressed: _submit, child: const Text('Add')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final listUrl = _listUrlController.text.trim();

    Navigator.pop(
      context,
      _SourceDraft(
        name: _nameController.text.trim(),
        listUrl: listUrl,
        category: _category,
        enabled: _enabled,
      ),
    );
  }

  bool _isValidUrl(String? value) {
    final raw = value?.trim() ?? '';
    final uri = Uri.tryParse(raw);
    if (uri == null) return false;
    return (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }
}

class _SourceDraft {
  const _SourceDraft({
    required this.name,
    required this.listUrl,
    required this.category,
    required this.enabled,
  });

  final String name;
  final String listUrl;
  final NewsCategory category;
  final bool enabled;
}

class _AppearanceSettings extends StatelessWidget {
  const _AppearanceSettings({
    required this.themeMode,
    required this.textScale,
    required this.onThemeModeChanged,
    required this.onTextScaleChanged,
  });

  final String themeMode;
  final double textScale;
  final ValueChanged<String> onThemeModeChanged;
  final ValueChanged<double> onTextScaleChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = const [
      _ThemeOption(label: 'System', value: 'system'),
      _ThemeOption(label: 'Light', value: 'light'),
      _ThemeOption(label: 'Dark', value: 'dark'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Theme',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: options.map((option) {
            final selected = themeMode == option.value;
            return ChoiceChip(
              label: Text(option.label),
              selected: selected,
              onSelected: (_) => onThemeModeChanged(option.value),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text(
          'Text size',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Adjust the reading size for the feed and article view.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        Slider(
          value: textScale,
          onChanged: onTextScaleChanged,
          min: 0.9,
          max: 1.3,
          divisions: 8,
          label: '${(textScale * 100).round()}%',
        ),
      ],
    );
  }
}

class _ThemeOption {
  const _ThemeOption({required this.label, required this.value});

  final String label;
  final String value;
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.value, required this.onChanged});

  final NewsCategory value;
  final ValueChanged<NewsCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.category_outlined, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<NewsCategory>(
            value: value,
            decoration: const InputDecoration(labelText: 'Category'),
            items: NewsCategory.values
                .map(
                  (category) => DropdownMenuItem(
                    value: category,
                    child: Text(category.label),
                  ),
                )
                .toList(),
            onChanged: (newValue) {
              if (newValue != null) onChanged(newValue);
            },
          ),
        ),
      ],
    );
  }
}

class _CompactCategoryMenu extends StatelessWidget {
  const _CompactCategoryMenu({required this.value, required this.onChanged});

  final NewsCategory value;
  final ValueChanged<NewsCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = {
      NewsCategory.local: 'Local',
      NewsCategory.regional: 'Regional',
      NewsCategory.international: 'Intl',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<NewsCategory>(
          value: value,
          isDense: true,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: theme.colorScheme.primary,
          ),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
          dropdownColor: theme.colorScheme.surface,
          items: NewsCategory.values
              .map(
                (category) => DropdownMenuItem(
                  value: category,
                  child: Text(labels[category] ?? category.label),
                ),
              )
              .toList(),
          onChanged: (newValue) {
            if (newValue != null) onChanged(newValue);
          },
        ),
      ),
    );
  }
}
