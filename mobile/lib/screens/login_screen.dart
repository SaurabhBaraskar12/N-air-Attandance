import 'package:flutter/material.dart';
import '../api_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usr = TextEditingController();
  final _pwd = TextEditingController();
  final _url = TextEditingController(text: ApiService.instance.baseUrl);
  bool _busy = false;
  bool _showUrl = false;
  String? _error;

  @override
  void dispose() {
    _usr.dispose();
    _pwd.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() { _busy = true; _error = null; });
    try {
      await ApiService.instance.setBaseUrl(_url.text);
      await ApiService.instance.login(_usr.text.trim(), _pwd.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.fingerprint, size: 72, color: Color(0xFF1565C0)),
                const SizedBox(height: 12),
                Text('Attendance Log',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 32),
                TextField(
                  controller: _usr,
                  decoration: const InputDecoration(
                      labelText: 'Username / Email',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person)),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pwd,
                  decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock)),
                  obscureText: true,
                  onSubmitted: (_) => _busy ? null : _login(),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: Icon(_showUrl ? Icons.expand_less : Icons.settings, size: 18),
                    label: const Text('Server settings'),
                    onPressed: () => setState(() => _showUrl = !_showUrl),
                  ),
                ),
                if (_showUrl)
                  TextField(
                    controller: _url,
                    decoration: const InputDecoration(
                        labelText: 'Server Base URL',
                        helperText: 'e.g. http://192.168.1.50:8000',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.link)),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!,
                          style: const TextStyle(color: Colors.red))),
                    ]),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _login,
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _busy
                      ? const SizedBox(
                          height: 22, width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Log In'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
