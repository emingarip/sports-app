class UserEvent {
  final String id;
  final String userId;
  final String eventType;
  final String entityType;
  final String entityId;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const UserEvent({
    required this.id,
    required this.userId,
    required this.eventType,
    required this.entityType,
    required this.entityId,
    this.metadata = const {},
    required this.createdAt,
  });

  factory UserEvent.fromJson(Map<String, dynamic> json) {
    return UserEvent(
      id: json['id'],
      userId: json['user_id'],
      eventType: json['event_type'],
      entityType: json['entity_type'],
      entityId: json['entity_id'],
      metadata: json['metadata'] ?? {},
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'event_type': eventType,
      'entity_type': entityType,
      'entity_id': entityId,
      'metadata': metadata,
    };
  }
}

class UserInterest {
  final String id;
  final String userId;
  final String entityType;
  final String entityId;
  final double interestScore;
  final int interactionCount;
  final DateTime lastInteraction;

  const UserInterest({
    required this.id,
    required this.userId,
    required this.entityType,
    required this.entityId,
    required this.interestScore,
    required this.interactionCount,
    required this.lastInteraction,
  });

  factory UserInterest.fromJson(Map<String, dynamic> json) {
    return UserInterest(
      id: json['id'],
      userId: json['user_id'],
      entityType: json['entity_type'],
      entityId: json['entity_id'],
      interestScore: (json['interest_score'] as num).toDouble(),
      interactionCount: json['interaction_count'],
      lastInteraction: DateTime.parse(json['last_interaction']),
    );
  }
}

class EntityRelation {
  final String id;
  final String entityAType;
  final String entityAId;
  final String entityBType;
  final String entityBId;
  final String relationType;
  final double strength;

  const EntityRelation({
    required this.id,
    required this.entityAType,
    required this.entityAId,
    required this.entityBType,
    required this.entityBId,
    required this.relationType,
    required this.strength,
  });

  factory EntityRelation.fromJson(Map<String, dynamic> json) {
    return EntityRelation(
      id: json['id'],
      entityAType: json['entity_a_type'],
      entityAId: json['entity_a_id'],
      entityBType: json['entity_b_type'],
      entityBId: json['entity_b_id'],
      relationType: json['relation_type'],
      strength: (json['strength'] as num).toDouble(),
    );
  }
}
