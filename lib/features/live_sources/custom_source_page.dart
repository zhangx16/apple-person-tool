import 'package:pure_live/core/index.dart';
import 'package:pure_live/domains/iptv/domain/custom_stream.dart';
import 'package:pure_live/domains/iptv/data/services/iptv_import_manager.dart';

class CustomSourcePage extends StatefulWidget {
  const CustomSourcePage({super.key});

  @override
  State<CustomSourcePage> createState() => _CustomSourcePageState();
}

class _CustomSourcePageState extends State<CustomSourcePage> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _userAgent = TextEditingController();
  final _referer = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final field in [_name, _url, _userAgent, _referer]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final draft = CustomStream(name: _name.text, url: _url.text, userAgent: _userAgent.text, referer: _referer.text);
      final playlist = draft.toM3u();
      // Duplicate names use the existing import confirmation; never silently
      // overwrite another playlist or bypass its channel reconciliation.
      final saved = await IptvImportManager().importFromWebString(playlist, draft.name.trim(), showTips: false);
      if (!mounted) return;
      if (saved) {
        Get.offNamed(RoutePath.kIptv);
      } else {
        setState(() => _error = i18n('custom_source_save_failed'));
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = i18n(e.message));
    } catch (_) {
      if (mounted) setState(() => _error = i18n('custom_source_save_failed'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n('live_custom_source'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Icon(Icons.add_to_queue_rounded, size: 52, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(i18n('custom_source_description'), style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 24),
              TextField(
                controller: _name,
                enabled: !_saving,
                decoration: InputDecoration(labelText: i18n('custom_source_name')),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _url,
                enabled: !_saving,
                keyboardType: TextInputType.url,
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                decoration: InputDecoration(labelText: i18n('custom_source_url'), hintText: 'https://…/live.m3u8'),
              ),
              const SizedBox(height: 16),
              ExpansionTile(
                title: Text(i18n('custom_source_headers')),
                children: [
                  TextField(
                    controller: _userAgent,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: 'User-Agent'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _referer,
                    enabled: !_saving,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'Referer'),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_rounded),
                label: Text(i18n('custom_source_save')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
