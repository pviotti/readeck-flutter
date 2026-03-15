class Bookmark {
  final String id;
  final String title;
  final String url;
  final String siteName;
  final String description;
  final int readingTime;
  final int readProgress;
  final bool isMarked;
  final bool isArchived;
  final List<String> labels;
  final String? thumbnailSrc;
  final DateTime created;
  final DateTime? published;

  const Bookmark({
    required this.id,
    required this.title,
    required this.url,
    required this.siteName,
    required this.description,
    required this.readingTime,
    required this.readProgress,
    required this.isMarked,
    required this.isArchived,
    required this.labels,
    required this.thumbnailSrc,
    required this.created,
    required this.published,
  });

  factory Bookmark.fromJson(Map<String, dynamic> json) {
    String? thumbnail;
    final resources = json['resources'] as Map<String, dynamic>?;
    if (resources != null) {
      final thumb = resources['thumbnail'] as Map<String, dynamic>?;
      if (thumb != null && thumb['src'] != null) {
        thumbnail = thumb['src'] as String;
      }
    }

    return Bookmark(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
      siteName: json['site_name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      readingTime: json['reading_time'] as int? ?? 0,
      readProgress: json['read_progress'] as int? ?? 0,
      isMarked: json['is_marked'] as bool? ?? false,
      isArchived: json['is_archived'] as bool? ?? false,
      labels: (json['labels'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      thumbnailSrc: thumbnail,
      created: DateTime.parse(json['created'] as String),
      published: json['published'] != null
          ? DateTime.tryParse(json['published'] as String)
          : null,
    );
  }
}
