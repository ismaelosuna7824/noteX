import '../../domain/services/title_generation_service.dart';

/// Stub adapter for external title generation API.
///
/// Replace with a real HTTP call to your backend when available.
class TitleApiAdapter implements TitleGenerationService {
  // final String _baseUrl;
  // TitleApiAdapter(this._baseUrl);

  @override
  Future<String> generateTitle(String contentSummary) async {
    // TODO: Replace with real HTTP call:
    // final response = await http.post(
    //   Uri.parse('$_baseUrl/generate-title'),
    //   body: jsonEncode({'summary': contentSummary}),
    //   headers: {'Content-Type': 'application/json'},
    // );
    // final data = jsonDecode(response.body);
    // return data['title'];

    // Stub: generate a simple title from first few words
    await Future.delayed(const Duration(milliseconds: 200));
    final words = contentSummary.split(' ').take(5).join(' ');
    return words.isEmpty ? 'Untitled Note' : words;
  }
}
