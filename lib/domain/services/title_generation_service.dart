/// Port (interface) for the external title generation API.
///
/// Sends note content summary and receives a generated title.
abstract class TitleGenerationService {
  /// Generate a title based on the note content summary.
  Future<String> generateTitle(String contentSummary);
}
