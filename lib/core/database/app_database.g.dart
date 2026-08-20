// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $DropletUserTable extends DropletUser
    with TableInfo<$DropletUserTable, DropletUserData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DropletUserTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pseudoMeta = const VerificationMeta('pseudo');
  @override
  late final GeneratedColumn<String> pseudo = GeneratedColumn<String>(
    'pseudo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarUrlMeta = const VerificationMeta(
    'avatarUrl',
  );
  @override
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
    'avatar_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _publicKeyMeta = const VerificationMeta(
    'publicKey',
  );
  @override
  late final GeneratedColumn<String> publicKey = GeneratedColumn<String>(
    'public_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, pseudo, avatarUrl, publicKey];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'droplet_user';
  @override
  VerificationContext validateIntegrity(
    Insertable<DropletUserData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('pseudo')) {
      context.handle(
        _pseudoMeta,
        pseudo.isAcceptableOrUnknown(data['pseudo']!, _pseudoMeta),
      );
    } else if (isInserting) {
      context.missing(_pseudoMeta);
    }
    if (data.containsKey('avatar_url')) {
      context.handle(
        _avatarUrlMeta,
        avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta),
      );
    }
    if (data.containsKey('public_key')) {
      context.handle(
        _publicKeyMeta,
        publicKey.isAcceptableOrUnknown(data['public_key']!, _publicKeyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DropletUserData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DropletUserData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      pseudo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pseudo'],
      )!,
      avatarUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_url'],
      ),
      publicKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}public_key'],
      ),
    );
  }

  @override
  $DropletUserTable createAlias(String alias) {
    return $DropletUserTable(attachedDatabase, alias);
  }
}

class DropletUserData extends DataClass implements Insertable<DropletUserData> {
  final String id;
  final String pseudo;
  final String? avatarUrl;
  final String? publicKey;
  const DropletUserData({
    required this.id,
    required this.pseudo,
    this.avatarUrl,
    this.publicKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['pseudo'] = Variable<String>(pseudo);
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    if (!nullToAbsent || publicKey != null) {
      map['public_key'] = Variable<String>(publicKey);
    }
    return map;
  }

  DropletUserCompanion toCompanion(bool nullToAbsent) {
    return DropletUserCompanion(
      id: Value(id),
      pseudo: Value(pseudo),
      avatarUrl: avatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarUrl),
      publicKey: publicKey == null && nullToAbsent
          ? const Value.absent()
          : Value(publicKey),
    );
  }

  factory DropletUserData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DropletUserData(
      id: serializer.fromJson<String>(json['id']),
      pseudo: serializer.fromJson<String>(json['pseudo']),
      avatarUrl: serializer.fromJson<String?>(json['avatarUrl']),
      publicKey: serializer.fromJson<String?>(json['publicKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'pseudo': serializer.toJson<String>(pseudo),
      'avatarUrl': serializer.toJson<String?>(avatarUrl),
      'publicKey': serializer.toJson<String?>(publicKey),
    };
  }

  DropletUserData copyWith({
    String? id,
    String? pseudo,
    Value<String?> avatarUrl = const Value.absent(),
    Value<String?> publicKey = const Value.absent(),
  }) => DropletUserData(
    id: id ?? this.id,
    pseudo: pseudo ?? this.pseudo,
    avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
    publicKey: publicKey.present ? publicKey.value : this.publicKey,
  );
  DropletUserData copyWithCompanion(DropletUserCompanion data) {
    return DropletUserData(
      id: data.id.present ? data.id.value : this.id,
      pseudo: data.pseudo.present ? data.pseudo.value : this.pseudo,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      publicKey: data.publicKey.present ? data.publicKey.value : this.publicKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DropletUserData(')
          ..write('id: $id, ')
          ..write('pseudo: $pseudo, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('publicKey: $publicKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, pseudo, avatarUrl, publicKey);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DropletUserData &&
          other.id == this.id &&
          other.pseudo == this.pseudo &&
          other.avatarUrl == this.avatarUrl &&
          other.publicKey == this.publicKey);
}

class DropletUserCompanion extends UpdateCompanion<DropletUserData> {
  final Value<String> id;
  final Value<String> pseudo;
  final Value<String?> avatarUrl;
  final Value<String?> publicKey;
  final Value<int> rowid;
  const DropletUserCompanion({
    this.id = const Value.absent(),
    this.pseudo = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.publicKey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DropletUserCompanion.insert({
    required String id,
    required String pseudo,
    this.avatarUrl = const Value.absent(),
    this.publicKey = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       pseudo = Value(pseudo);
  static Insertable<DropletUserData> custom({
    Expression<String>? id,
    Expression<String>? pseudo,
    Expression<String>? avatarUrl,
    Expression<String>? publicKey,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (pseudo != null) 'pseudo': pseudo,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (publicKey != null) 'public_key': publicKey,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DropletUserCompanion copyWith({
    Value<String>? id,
    Value<String>? pseudo,
    Value<String?>? avatarUrl,
    Value<String?>? publicKey,
    Value<int>? rowid,
  }) {
    return DropletUserCompanion(
      id: id ?? this.id,
      pseudo: pseudo ?? this.pseudo,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      publicKey: publicKey ?? this.publicKey,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (pseudo.present) {
      map['pseudo'] = Variable<String>(pseudo.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (publicKey.present) {
      map['public_key'] = Variable<String>(publicKey.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DropletUserCompanion(')
          ..write('id: $id, ')
          ..write('pseudo: $pseudo, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('publicKey: $publicKey, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MeshMessagesTable extends MeshMessages
    with TableInfo<$MeshMessagesTable, MeshMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MeshMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorPseudoMeta = const VerificationMeta(
    'authorPseudo',
  );
  @override
  late final GeneratedColumn<String> authorPseudo = GeneratedColumn<String>(
    'author_pseudo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<int> timestamp = GeneratedColumn<int>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderIdMeta = const VerificationMeta(
    'senderId',
  );
  @override
  late final GeneratedColumn<String> senderId = GeneratedColumn<String>(
    'sender_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _imageUrlMeta = const VerificationMeta(
    'imageUrl',
  );
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
    'image_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _audioUrlMeta = const VerificationMeta(
    'audioUrl',
  );
  @override
  late final GeneratedColumn<String> audioUrl = GeneratedColumn<String>(
    'audio_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hopCountMeta = const VerificationMeta(
    'hopCount',
  );
  @override
  late final GeneratedColumn<int> hopCount = GeneratedColumn<int>(
    'hop_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reactionsMeta = const VerificationMeta(
    'reactions',
  );
  @override
  late final GeneratedColumn<String> reactions = GeneratedColumn<String>(
    'reactions',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileIdMeta = const VerificationMeta('fileId');
  @override
  late final GeneratedColumn<String> fileId = GeneratedColumn<String>(
    'file_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileSizeMeta = const VerificationMeta(
    'fileSize',
  );
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
    'file_size',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileMimeTypeMeta = const VerificationMeta(
    'fileMimeType',
  );
  @override
  late final GeneratedColumn<String> fileMimeType = GeneratedColumn<String>(
    'file_mime_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _replyToIdMeta = const VerificationMeta(
    'replyToId',
  );
  @override
  late final GeneratedColumn<String> replyToId = GeneratedColumn<String>(
    'reply_to_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _routeInfoMeta = const VerificationMeta(
    'routeInfo',
  );
  @override
  late final GeneratedColumn<String> routeInfo = GeneratedColumn<String>(
    'route_info',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _readAtMeta = const VerificationMeta('readAt');
  @override
  late final GeneratedColumn<int> readAt = GeneratedColumn<int>(
    'read_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    authorPseudo,
    content,
    type,
    timestamp,
    senderId,
    targetId,
    imageUrl,
    audioUrl,
    hopCount,
    reactions,
    updatedAt,
    syncStatus,
    fileId,
    fileName,
    fileSize,
    fileMimeType,
    replyToId,
    status,
    routeInfo,
    readAt,
    groupId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mesh_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<MeshMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('author_pseudo')) {
      context.handle(
        _authorPseudoMeta,
        authorPseudo.isAcceptableOrUnknown(
          data['author_pseudo']!,
          _authorPseudoMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_authorPseudoMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('sender_id')) {
      context.handle(
        _senderIdMeta,
        senderId.isAcceptableOrUnknown(data['sender_id']!, _senderIdMeta),
      );
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    }
    if (data.containsKey('image_url')) {
      context.handle(
        _imageUrlMeta,
        imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta),
      );
    }
    if (data.containsKey('audio_url')) {
      context.handle(
        _audioUrlMeta,
        audioUrl.isAcceptableOrUnknown(data['audio_url']!, _audioUrlMeta),
      );
    }
    if (data.containsKey('hop_count')) {
      context.handle(
        _hopCountMeta,
        hopCount.isAcceptableOrUnknown(data['hop_count']!, _hopCountMeta),
      );
    } else if (isInserting) {
      context.missing(_hopCountMeta);
    }
    if (data.containsKey('reactions')) {
      context.handle(
        _reactionsMeta,
        reactions.isAcceptableOrUnknown(data['reactions']!, _reactionsMeta),
      );
    } else if (isInserting) {
      context.missing(_reactionsMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    } else if (isInserting) {
      context.missing(_syncStatusMeta);
    }
    if (data.containsKey('file_id')) {
      context.handle(
        _fileIdMeta,
        fileId.isAcceptableOrUnknown(data['file_id']!, _fileIdMeta),
      );
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    }
    if (data.containsKey('file_size')) {
      context.handle(
        _fileSizeMeta,
        fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta),
      );
    }
    if (data.containsKey('file_mime_type')) {
      context.handle(
        _fileMimeTypeMeta,
        fileMimeType.isAcceptableOrUnknown(
          data['file_mime_type']!,
          _fileMimeTypeMeta,
        ),
      );
    }
    if (data.containsKey('reply_to_id')) {
      context.handle(
        _replyToIdMeta,
        replyToId.isAcceptableOrUnknown(data['reply_to_id']!, _replyToIdMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('route_info')) {
      context.handle(
        _routeInfoMeta,
        routeInfo.isAcceptableOrUnknown(data['route_info']!, _routeInfoMeta),
      );
    }
    if (data.containsKey('read_at')) {
      context.handle(
        _readAtMeta,
        readAt.isAcceptableOrUnknown(data['read_at']!, _readAtMeta),
      );
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MeshMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MeshMessage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      authorPseudo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_pseudo'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp'],
      )!,
      senderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_id'],
      ),
      targetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_id'],
      ),
      imageUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_url'],
      ),
      audioUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_url'],
      ),
      hopCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hop_count'],
      )!,
      reactions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reactions'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
      fileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_id'],
      ),
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      ),
      fileSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size'],
      ),
      fileMimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_mime_type'],
      ),
      replyToId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_to_id'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      routeInfo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}route_info'],
      ),
      readAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}read_at'],
      ),
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      ),
    );
  }

  @override
  $MeshMessagesTable createAlias(String alias) {
    return $MeshMessagesTable(attachedDatabase, alias);
  }
}

class MeshMessage extends DataClass implements Insertable<MeshMessage> {
  final String id;
  final String authorPseudo;
  final String content;
  final String type;
  final int timestamp;
  final String? senderId;
  final String? targetId;
  final String? imageUrl;
  final String? audioUrl;
  final int hopCount;
  final String reactions;
  final int updatedAt;
  final String syncStatus;
  final String? fileId;
  final String? fileName;
  final int? fileSize;
  final String? fileMimeType;
  final String? replyToId;
  final String status;
  final String? routeInfo;
  final int? readAt;

  /// Groupe de discussion ciblé — distinct de [targetId], qui reste réservé
  /// à l'adressage 1:1. Null pour les messages 1:1 ou de diffusion.
  final String? groupId;
  const MeshMessage({
    required this.id,
    required this.authorPseudo,
    required this.content,
    required this.type,
    required this.timestamp,
    this.senderId,
    this.targetId,
    this.imageUrl,
    this.audioUrl,
    required this.hopCount,
    required this.reactions,
    required this.updatedAt,
    required this.syncStatus,
    this.fileId,
    this.fileName,
    this.fileSize,
    this.fileMimeType,
    this.replyToId,
    required this.status,
    this.routeInfo,
    this.readAt,
    this.groupId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['author_pseudo'] = Variable<String>(authorPseudo);
    map['content'] = Variable<String>(content);
    map['type'] = Variable<String>(type);
    map['timestamp'] = Variable<int>(timestamp);
    if (!nullToAbsent || senderId != null) {
      map['sender_id'] = Variable<String>(senderId);
    }
    if (!nullToAbsent || targetId != null) {
      map['target_id'] = Variable<String>(targetId);
    }
    if (!nullToAbsent || imageUrl != null) {
      map['image_url'] = Variable<String>(imageUrl);
    }
    if (!nullToAbsent || audioUrl != null) {
      map['audio_url'] = Variable<String>(audioUrl);
    }
    map['hop_count'] = Variable<int>(hopCount);
    map['reactions'] = Variable<String>(reactions);
    map['updated_at'] = Variable<int>(updatedAt);
    map['sync_status'] = Variable<String>(syncStatus);
    if (!nullToAbsent || fileId != null) {
      map['file_id'] = Variable<String>(fileId);
    }
    if (!nullToAbsent || fileName != null) {
      map['file_name'] = Variable<String>(fileName);
    }
    if (!nullToAbsent || fileSize != null) {
      map['file_size'] = Variable<int>(fileSize);
    }
    if (!nullToAbsent || fileMimeType != null) {
      map['file_mime_type'] = Variable<String>(fileMimeType);
    }
    if (!nullToAbsent || replyToId != null) {
      map['reply_to_id'] = Variable<String>(replyToId);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || routeInfo != null) {
      map['route_info'] = Variable<String>(routeInfo);
    }
    if (!nullToAbsent || readAt != null) {
      map['read_at'] = Variable<int>(readAt);
    }
    if (!nullToAbsent || groupId != null) {
      map['group_id'] = Variable<String>(groupId);
    }
    return map;
  }

  MeshMessagesCompanion toCompanion(bool nullToAbsent) {
    return MeshMessagesCompanion(
      id: Value(id),
      authorPseudo: Value(authorPseudo),
      content: Value(content),
      type: Value(type),
      timestamp: Value(timestamp),
      senderId: senderId == null && nullToAbsent
          ? const Value.absent()
          : Value(senderId),
      targetId: targetId == null && nullToAbsent
          ? const Value.absent()
          : Value(targetId),
      imageUrl: imageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(imageUrl),
      audioUrl: audioUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(audioUrl),
      hopCount: Value(hopCount),
      reactions: Value(reactions),
      updatedAt: Value(updatedAt),
      syncStatus: Value(syncStatus),
      fileId: fileId == null && nullToAbsent
          ? const Value.absent()
          : Value(fileId),
      fileName: fileName == null && nullToAbsent
          ? const Value.absent()
          : Value(fileName),
      fileSize: fileSize == null && nullToAbsent
          ? const Value.absent()
          : Value(fileSize),
      fileMimeType: fileMimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(fileMimeType),
      replyToId: replyToId == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToId),
      status: Value(status),
      routeInfo: routeInfo == null && nullToAbsent
          ? const Value.absent()
          : Value(routeInfo),
      readAt: readAt == null && nullToAbsent
          ? const Value.absent()
          : Value(readAt),
      groupId: groupId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupId),
    );
  }

  factory MeshMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MeshMessage(
      id: serializer.fromJson<String>(json['id']),
      authorPseudo: serializer.fromJson<String>(json['authorPseudo']),
      content: serializer.fromJson<String>(json['content']),
      type: serializer.fromJson<String>(json['type']),
      timestamp: serializer.fromJson<int>(json['timestamp']),
      senderId: serializer.fromJson<String?>(json['senderId']),
      targetId: serializer.fromJson<String?>(json['targetId']),
      imageUrl: serializer.fromJson<String?>(json['imageUrl']),
      audioUrl: serializer.fromJson<String?>(json['audioUrl']),
      hopCount: serializer.fromJson<int>(json['hopCount']),
      reactions: serializer.fromJson<String>(json['reactions']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      fileId: serializer.fromJson<String?>(json['fileId']),
      fileName: serializer.fromJson<String?>(json['fileName']),
      fileSize: serializer.fromJson<int?>(json['fileSize']),
      fileMimeType: serializer.fromJson<String?>(json['fileMimeType']),
      replyToId: serializer.fromJson<String?>(json['replyToId']),
      status: serializer.fromJson<String>(json['status']),
      routeInfo: serializer.fromJson<String?>(json['routeInfo']),
      readAt: serializer.fromJson<int?>(json['readAt']),
      groupId: serializer.fromJson<String?>(json['groupId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'authorPseudo': serializer.toJson<String>(authorPseudo),
      'content': serializer.toJson<String>(content),
      'type': serializer.toJson<String>(type),
      'timestamp': serializer.toJson<int>(timestamp),
      'senderId': serializer.toJson<String?>(senderId),
      'targetId': serializer.toJson<String?>(targetId),
      'imageUrl': serializer.toJson<String?>(imageUrl),
      'audioUrl': serializer.toJson<String?>(audioUrl),
      'hopCount': serializer.toJson<int>(hopCount),
      'reactions': serializer.toJson<String>(reactions),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'fileId': serializer.toJson<String?>(fileId),
      'fileName': serializer.toJson<String?>(fileName),
      'fileSize': serializer.toJson<int?>(fileSize),
      'fileMimeType': serializer.toJson<String?>(fileMimeType),
      'replyToId': serializer.toJson<String?>(replyToId),
      'status': serializer.toJson<String>(status),
      'routeInfo': serializer.toJson<String?>(routeInfo),
      'readAt': serializer.toJson<int?>(readAt),
      'groupId': serializer.toJson<String?>(groupId),
    };
  }

  MeshMessage copyWith({
    String? id,
    String? authorPseudo,
    String? content,
    String? type,
    int? timestamp,
    Value<String?> senderId = const Value.absent(),
    Value<String?> targetId = const Value.absent(),
    Value<String?> imageUrl = const Value.absent(),
    Value<String?> audioUrl = const Value.absent(),
    int? hopCount,
    String? reactions,
    int? updatedAt,
    String? syncStatus,
    Value<String?> fileId = const Value.absent(),
    Value<String?> fileName = const Value.absent(),
    Value<int?> fileSize = const Value.absent(),
    Value<String?> fileMimeType = const Value.absent(),
    Value<String?> replyToId = const Value.absent(),
    String? status,
    Value<String?> routeInfo = const Value.absent(),
    Value<int?> readAt = const Value.absent(),
    Value<String?> groupId = const Value.absent(),
  }) => MeshMessage(
    id: id ?? this.id,
    authorPseudo: authorPseudo ?? this.authorPseudo,
    content: content ?? this.content,
    type: type ?? this.type,
    timestamp: timestamp ?? this.timestamp,
    senderId: senderId.present ? senderId.value : this.senderId,
    targetId: targetId.present ? targetId.value : this.targetId,
    imageUrl: imageUrl.present ? imageUrl.value : this.imageUrl,
    audioUrl: audioUrl.present ? audioUrl.value : this.audioUrl,
    hopCount: hopCount ?? this.hopCount,
    reactions: reactions ?? this.reactions,
    updatedAt: updatedAt ?? this.updatedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    fileId: fileId.present ? fileId.value : this.fileId,
    fileName: fileName.present ? fileName.value : this.fileName,
    fileSize: fileSize.present ? fileSize.value : this.fileSize,
    fileMimeType: fileMimeType.present ? fileMimeType.value : this.fileMimeType,
    replyToId: replyToId.present ? replyToId.value : this.replyToId,
    status: status ?? this.status,
    routeInfo: routeInfo.present ? routeInfo.value : this.routeInfo,
    readAt: readAt.present ? readAt.value : this.readAt,
    groupId: groupId.present ? groupId.value : this.groupId,
  );
  MeshMessage copyWithCompanion(MeshMessagesCompanion data) {
    return MeshMessage(
      id: data.id.present ? data.id.value : this.id,
      authorPseudo: data.authorPseudo.present
          ? data.authorPseudo.value
          : this.authorPseudo,
      content: data.content.present ? data.content.value : this.content,
      type: data.type.present ? data.type.value : this.type,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      senderId: data.senderId.present ? data.senderId.value : this.senderId,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      audioUrl: data.audioUrl.present ? data.audioUrl.value : this.audioUrl,
      hopCount: data.hopCount.present ? data.hopCount.value : this.hopCount,
      reactions: data.reactions.present ? data.reactions.value : this.reactions,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      fileId: data.fileId.present ? data.fileId.value : this.fileId,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      fileMimeType: data.fileMimeType.present
          ? data.fileMimeType.value
          : this.fileMimeType,
      replyToId: data.replyToId.present ? data.replyToId.value : this.replyToId,
      status: data.status.present ? data.status.value : this.status,
      routeInfo: data.routeInfo.present ? data.routeInfo.value : this.routeInfo,
      readAt: data.readAt.present ? data.readAt.value : this.readAt,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MeshMessage(')
          ..write('id: $id, ')
          ..write('authorPseudo: $authorPseudo, ')
          ..write('content: $content, ')
          ..write('type: $type, ')
          ..write('timestamp: $timestamp, ')
          ..write('senderId: $senderId, ')
          ..write('targetId: $targetId, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('audioUrl: $audioUrl, ')
          ..write('hopCount: $hopCount, ')
          ..write('reactions: $reactions, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('fileId: $fileId, ')
          ..write('fileName: $fileName, ')
          ..write('fileSize: $fileSize, ')
          ..write('fileMimeType: $fileMimeType, ')
          ..write('replyToId: $replyToId, ')
          ..write('status: $status, ')
          ..write('routeInfo: $routeInfo, ')
          ..write('readAt: $readAt, ')
          ..write('groupId: $groupId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    authorPseudo,
    content,
    type,
    timestamp,
    senderId,
    targetId,
    imageUrl,
    audioUrl,
    hopCount,
    reactions,
    updatedAt,
    syncStatus,
    fileId,
    fileName,
    fileSize,
    fileMimeType,
    replyToId,
    status,
    routeInfo,
    readAt,
    groupId,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MeshMessage &&
          other.id == this.id &&
          other.authorPseudo == this.authorPseudo &&
          other.content == this.content &&
          other.type == this.type &&
          other.timestamp == this.timestamp &&
          other.senderId == this.senderId &&
          other.targetId == this.targetId &&
          other.imageUrl == this.imageUrl &&
          other.audioUrl == this.audioUrl &&
          other.hopCount == this.hopCount &&
          other.reactions == this.reactions &&
          other.updatedAt == this.updatedAt &&
          other.syncStatus == this.syncStatus &&
          other.fileId == this.fileId &&
          other.fileName == this.fileName &&
          other.fileSize == this.fileSize &&
          other.fileMimeType == this.fileMimeType &&
          other.replyToId == this.replyToId &&
          other.status == this.status &&
          other.routeInfo == this.routeInfo &&
          other.readAt == this.readAt &&
          other.groupId == this.groupId);
}

class MeshMessagesCompanion extends UpdateCompanion<MeshMessage> {
  final Value<String> id;
  final Value<String> authorPseudo;
  final Value<String> content;
  final Value<String> type;
  final Value<int> timestamp;
  final Value<String?> senderId;
  final Value<String?> targetId;
  final Value<String?> imageUrl;
  final Value<String?> audioUrl;
  final Value<int> hopCount;
  final Value<String> reactions;
  final Value<int> updatedAt;
  final Value<String> syncStatus;
  final Value<String?> fileId;
  final Value<String?> fileName;
  final Value<int?> fileSize;
  final Value<String?> fileMimeType;
  final Value<String?> replyToId;
  final Value<String> status;
  final Value<String?> routeInfo;
  final Value<int?> readAt;
  final Value<String?> groupId;
  final Value<int> rowid;
  const MeshMessagesCompanion({
    this.id = const Value.absent(),
    this.authorPseudo = const Value.absent(),
    this.content = const Value.absent(),
    this.type = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.senderId = const Value.absent(),
    this.targetId = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.audioUrl = const Value.absent(),
    this.hopCount = const Value.absent(),
    this.reactions = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.fileId = const Value.absent(),
    this.fileName = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.fileMimeType = const Value.absent(),
    this.replyToId = const Value.absent(),
    this.status = const Value.absent(),
    this.routeInfo = const Value.absent(),
    this.readAt = const Value.absent(),
    this.groupId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MeshMessagesCompanion.insert({
    required String id,
    required String authorPseudo,
    required String content,
    required String type,
    required int timestamp,
    this.senderId = const Value.absent(),
    this.targetId = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.audioUrl = const Value.absent(),
    required int hopCount,
    required String reactions,
    required int updatedAt,
    required String syncStatus,
    this.fileId = const Value.absent(),
    this.fileName = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.fileMimeType = const Value.absent(),
    this.replyToId = const Value.absent(),
    required String status,
    this.routeInfo = const Value.absent(),
    this.readAt = const Value.absent(),
    this.groupId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       authorPseudo = Value(authorPseudo),
       content = Value(content),
       type = Value(type),
       timestamp = Value(timestamp),
       hopCount = Value(hopCount),
       reactions = Value(reactions),
       updatedAt = Value(updatedAt),
       syncStatus = Value(syncStatus),
       status = Value(status);
  static Insertable<MeshMessage> custom({
    Expression<String>? id,
    Expression<String>? authorPseudo,
    Expression<String>? content,
    Expression<String>? type,
    Expression<int>? timestamp,
    Expression<String>? senderId,
    Expression<String>? targetId,
    Expression<String>? imageUrl,
    Expression<String>? audioUrl,
    Expression<int>? hopCount,
    Expression<String>? reactions,
    Expression<int>? updatedAt,
    Expression<String>? syncStatus,
    Expression<String>? fileId,
    Expression<String>? fileName,
    Expression<int>? fileSize,
    Expression<String>? fileMimeType,
    Expression<String>? replyToId,
    Expression<String>? status,
    Expression<String>? routeInfo,
    Expression<int>? readAt,
    Expression<String>? groupId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (authorPseudo != null) 'author_pseudo': authorPseudo,
      if (content != null) 'content': content,
      if (type != null) 'type': type,
      if (timestamp != null) 'timestamp': timestamp,
      if (senderId != null) 'sender_id': senderId,
      if (targetId != null) 'target_id': targetId,
      if (imageUrl != null) 'image_url': imageUrl,
      if (audioUrl != null) 'audio_url': audioUrl,
      if (hopCount != null) 'hop_count': hopCount,
      if (reactions != null) 'reactions': reactions,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (fileId != null) 'file_id': fileId,
      if (fileName != null) 'file_name': fileName,
      if (fileSize != null) 'file_size': fileSize,
      if (fileMimeType != null) 'file_mime_type': fileMimeType,
      if (replyToId != null) 'reply_to_id': replyToId,
      if (status != null) 'status': status,
      if (routeInfo != null) 'route_info': routeInfo,
      if (readAt != null) 'read_at': readAt,
      if (groupId != null) 'group_id': groupId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MeshMessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? authorPseudo,
    Value<String>? content,
    Value<String>? type,
    Value<int>? timestamp,
    Value<String?>? senderId,
    Value<String?>? targetId,
    Value<String?>? imageUrl,
    Value<String?>? audioUrl,
    Value<int>? hopCount,
    Value<String>? reactions,
    Value<int>? updatedAt,
    Value<String>? syncStatus,
    Value<String?>? fileId,
    Value<String?>? fileName,
    Value<int?>? fileSize,
    Value<String?>? fileMimeType,
    Value<String?>? replyToId,
    Value<String>? status,
    Value<String?>? routeInfo,
    Value<int?>? readAt,
    Value<String?>? groupId,
    Value<int>? rowid,
  }) {
    return MeshMessagesCompanion(
      id: id ?? this.id,
      authorPseudo: authorPseudo ?? this.authorPseudo,
      content: content ?? this.content,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      senderId: senderId ?? this.senderId,
      targetId: targetId ?? this.targetId,
      imageUrl: imageUrl ?? this.imageUrl,
      audioUrl: audioUrl ?? this.audioUrl,
      hopCount: hopCount ?? this.hopCount,
      reactions: reactions ?? this.reactions,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      fileId: fileId ?? this.fileId,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      fileMimeType: fileMimeType ?? this.fileMimeType,
      replyToId: replyToId ?? this.replyToId,
      status: status ?? this.status,
      routeInfo: routeInfo ?? this.routeInfo,
      readAt: readAt ?? this.readAt,
      groupId: groupId ?? this.groupId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (authorPseudo.present) {
      map['author_pseudo'] = Variable<String>(authorPseudo.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<int>(timestamp.value);
    }
    if (senderId.present) {
      map['sender_id'] = Variable<String>(senderId.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (audioUrl.present) {
      map['audio_url'] = Variable<String>(audioUrl.value);
    }
    if (hopCount.present) {
      map['hop_count'] = Variable<int>(hopCount.value);
    }
    if (reactions.present) {
      map['reactions'] = Variable<String>(reactions.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (fileId.present) {
      map['file_id'] = Variable<String>(fileId.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (fileMimeType.present) {
      map['file_mime_type'] = Variable<String>(fileMimeType.value);
    }
    if (replyToId.present) {
      map['reply_to_id'] = Variable<String>(replyToId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (routeInfo.present) {
      map['route_info'] = Variable<String>(routeInfo.value);
    }
    if (readAt.present) {
      map['read_at'] = Variable<int>(readAt.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MeshMessagesCompanion(')
          ..write('id: $id, ')
          ..write('authorPseudo: $authorPseudo, ')
          ..write('content: $content, ')
          ..write('type: $type, ')
          ..write('timestamp: $timestamp, ')
          ..write('senderId: $senderId, ')
          ..write('targetId: $targetId, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('audioUrl: $audioUrl, ')
          ..write('hopCount: $hopCount, ')
          ..write('reactions: $reactions, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('fileId: $fileId, ')
          ..write('fileName: $fileName, ')
          ..write('fileSize: $fileSize, ')
          ..write('fileMimeType: $fileMimeType, ')
          ..write('replyToId: $replyToId, ')
          ..write('status: $status, ')
          ..write('routeInfo: $routeInfo, ')
          ..write('readAt: $readAt, ')
          ..write('groupId: $groupId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MeshGroupsTable extends MeshGroups
    with TableInfo<$MeshGroupsTable, MeshGroup> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MeshGroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarUrlMeta = const VerificationMeta(
    'avatarUrl',
  );
  @override
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
    'avatar_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdByMeta = const VerificationMeta(
    'createdBy',
  );
  @override
  late final GeneratedColumn<String> createdBy = GeneratedColumn<String>(
    'created_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    avatarUrl,
    createdBy,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mesh_groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<MeshGroup> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('avatar_url')) {
      context.handle(
        _avatarUrlMeta,
        avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta),
      );
    }
    if (data.containsKey('created_by')) {
      context.handle(
        _createdByMeta,
        createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta),
      );
    } else if (isInserting) {
      context.missing(_createdByMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MeshGroup map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MeshGroup(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      avatarUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_url'],
      ),
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $MeshGroupsTable createAlias(String alias) {
    return $MeshGroupsTable(attachedDatabase, alias);
  }
}

class MeshGroup extends DataClass implements Insertable<MeshGroup> {
  final String id;
  final String name;
  final String? avatarUrl;
  final String createdBy;
  final int createdAt;
  final int updatedAt;
  const MeshGroup({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    map['created_by'] = Variable<String>(createdBy);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  MeshGroupsCompanion toCompanion(bool nullToAbsent) {
    return MeshGroupsCompanion(
      id: Value(id),
      name: Value(name),
      avatarUrl: avatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarUrl),
      createdBy: Value(createdBy),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory MeshGroup.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MeshGroup(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      avatarUrl: serializer.fromJson<String?>(json['avatarUrl']),
      createdBy: serializer.fromJson<String>(json['createdBy']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'avatarUrl': serializer.toJson<String?>(avatarUrl),
      'createdBy': serializer.toJson<String>(createdBy),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  MeshGroup copyWith({
    String? id,
    String? name,
    Value<String?> avatarUrl = const Value.absent(),
    String? createdBy,
    int? createdAt,
    int? updatedAt,
  }) => MeshGroup(
    id: id ?? this.id,
    name: name ?? this.name,
    avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
    createdBy: createdBy ?? this.createdBy,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  MeshGroup copyWithCompanion(MeshGroupsCompanion data) {
    return MeshGroup(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MeshGroup(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('createdBy: $createdBy, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, avatarUrl, createdBy, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MeshGroup &&
          other.id == this.id &&
          other.name == this.name &&
          other.avatarUrl == this.avatarUrl &&
          other.createdBy == this.createdBy &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class MeshGroupsCompanion extends UpdateCompanion<MeshGroup> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> avatarUrl;
  final Value<String> createdBy;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const MeshGroupsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MeshGroupsCompanion.insert({
    required String id,
    required String name,
    this.avatarUrl = const Value.absent(),
    required String createdBy,
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdBy = Value(createdBy),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<MeshGroup> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? avatarUrl,
    Expression<String>? createdBy,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (createdBy != null) 'created_by': createdBy,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MeshGroupsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? avatarUrl,
    Value<String>? createdBy,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return MeshGroupsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MeshGroupsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('createdBy: $createdBy, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GroupMembersTable extends GroupMembers
    with TableInfo<$GroupMembersTable, GroupMember> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GroupMembersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerIdMeta = const VerificationMeta('peerId');
  @override
  late final GeneratedColumn<String> peerId = GeneratedColumn<String>(
    'peer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _removedAtMeta = const VerificationMeta(
    'removedAt',
  );
  @override
  late final GeneratedColumn<int> removedAt = GeneratedColumn<int>(
    'removed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedByMeta = const VerificationMeta(
    'addedBy',
  );
  @override
  late final GeneratedColumn<String> addedBy = GeneratedColumn<String>(
    'added_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    groupId,
    peerId,
    role,
    addedAt,
    removedAt,
    addedBy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'group_members';
  @override
  VerificationContext validateIntegrity(
    Insertable<GroupMember> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('peer_id')) {
      context.handle(
        _peerIdMeta,
        peerId.isAcceptableOrUnknown(data['peer_id']!, _peerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_peerIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    if (data.containsKey('removed_at')) {
      context.handle(
        _removedAtMeta,
        removedAt.isAcceptableOrUnknown(data['removed_at']!, _removedAtMeta),
      );
    }
    if (data.containsKey('added_by')) {
      context.handle(
        _addedByMeta,
        addedBy.isAcceptableOrUnknown(data['added_by']!, _addedByMeta),
      );
    } else if (isInserting) {
      context.missing(_addedByMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId, peerId};
  @override
  GroupMember map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GroupMember(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      peerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      )!,
      removedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}removed_at'],
      ),
      addedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}added_by'],
      )!,
    );
  }

  @override
  $GroupMembersTable createAlias(String alias) {
    return $GroupMembersTable(attachedDatabase, alias);
  }
}

class GroupMember extends DataClass implements Insertable<GroupMember> {
  final String groupId;
  final String peerId;
  final String role;
  final int addedAt;
  final int? removedAt;
  final String addedBy;
  const GroupMember({
    required this.groupId,
    required this.peerId,
    required this.role,
    required this.addedAt,
    this.removedAt,
    required this.addedBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['peer_id'] = Variable<String>(peerId);
    map['role'] = Variable<String>(role);
    map['added_at'] = Variable<int>(addedAt);
    if (!nullToAbsent || removedAt != null) {
      map['removed_at'] = Variable<int>(removedAt);
    }
    map['added_by'] = Variable<String>(addedBy);
    return map;
  }

  GroupMembersCompanion toCompanion(bool nullToAbsent) {
    return GroupMembersCompanion(
      groupId: Value(groupId),
      peerId: Value(peerId),
      role: Value(role),
      addedAt: Value(addedAt),
      removedAt: removedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(removedAt),
      addedBy: Value(addedBy),
    );
  }

  factory GroupMember.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GroupMember(
      groupId: serializer.fromJson<String>(json['groupId']),
      peerId: serializer.fromJson<String>(json['peerId']),
      role: serializer.fromJson<String>(json['role']),
      addedAt: serializer.fromJson<int>(json['addedAt']),
      removedAt: serializer.fromJson<int?>(json['removedAt']),
      addedBy: serializer.fromJson<String>(json['addedBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'peerId': serializer.toJson<String>(peerId),
      'role': serializer.toJson<String>(role),
      'addedAt': serializer.toJson<int>(addedAt),
      'removedAt': serializer.toJson<int?>(removedAt),
      'addedBy': serializer.toJson<String>(addedBy),
    };
  }

  GroupMember copyWith({
    String? groupId,
    String? peerId,
    String? role,
    int? addedAt,
    Value<int?> removedAt = const Value.absent(),
    String? addedBy,
  }) => GroupMember(
    groupId: groupId ?? this.groupId,
    peerId: peerId ?? this.peerId,
    role: role ?? this.role,
    addedAt: addedAt ?? this.addedAt,
    removedAt: removedAt.present ? removedAt.value : this.removedAt,
    addedBy: addedBy ?? this.addedBy,
  );
  GroupMember copyWithCompanion(GroupMembersCompanion data) {
    return GroupMember(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      peerId: data.peerId.present ? data.peerId.value : this.peerId,
      role: data.role.present ? data.role.value : this.role,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      removedAt: data.removedAt.present ? data.removedAt.value : this.removedAt,
      addedBy: data.addedBy.present ? data.addedBy.value : this.addedBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GroupMember(')
          ..write('groupId: $groupId, ')
          ..write('peerId: $peerId, ')
          ..write('role: $role, ')
          ..write('addedAt: $addedAt, ')
          ..write('removedAt: $removedAt, ')
          ..write('addedBy: $addedBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(groupId, peerId, role, addedAt, removedAt, addedBy);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GroupMember &&
          other.groupId == this.groupId &&
          other.peerId == this.peerId &&
          other.role == this.role &&
          other.addedAt == this.addedAt &&
          other.removedAt == this.removedAt &&
          other.addedBy == this.addedBy);
}

class GroupMembersCompanion extends UpdateCompanion<GroupMember> {
  final Value<String> groupId;
  final Value<String> peerId;
  final Value<String> role;
  final Value<int> addedAt;
  final Value<int?> removedAt;
  final Value<String> addedBy;
  final Value<int> rowid;
  const GroupMembersCompanion({
    this.groupId = const Value.absent(),
    this.peerId = const Value.absent(),
    this.role = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.removedAt = const Value.absent(),
    this.addedBy = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GroupMembersCompanion.insert({
    required String groupId,
    required String peerId,
    required String role,
    required int addedAt,
    this.removedAt = const Value.absent(),
    required String addedBy,
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       peerId = Value(peerId),
       role = Value(role),
       addedAt = Value(addedAt),
       addedBy = Value(addedBy);
  static Insertable<GroupMember> custom({
    Expression<String>? groupId,
    Expression<String>? peerId,
    Expression<String>? role,
    Expression<int>? addedAt,
    Expression<int>? removedAt,
    Expression<String>? addedBy,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (peerId != null) 'peer_id': peerId,
      if (role != null) 'role': role,
      if (addedAt != null) 'added_at': addedAt,
      if (removedAt != null) 'removed_at': removedAt,
      if (addedBy != null) 'added_by': addedBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GroupMembersCompanion copyWith({
    Value<String>? groupId,
    Value<String>? peerId,
    Value<String>? role,
    Value<int>? addedAt,
    Value<int?>? removedAt,
    Value<String>? addedBy,
    Value<int>? rowid,
  }) {
    return GroupMembersCompanion(
      groupId: groupId ?? this.groupId,
      peerId: peerId ?? this.peerId,
      role: role ?? this.role,
      addedAt: addedAt ?? this.addedAt,
      removedAt: removedAt ?? this.removedAt,
      addedBy: addedBy ?? this.addedBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (peerId.present) {
      map['peer_id'] = Variable<String>(peerId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (removedAt.present) {
      map['removed_at'] = Variable<int>(removedAt.value);
    }
    if (addedBy.present) {
      map['added_by'] = Variable<String>(addedBy.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GroupMembersCompanion(')
          ..write('groupId: $groupId, ')
          ..write('peerId: $peerId, ')
          ..write('role: $role, ')
          ..write('addedAt: $addedAt, ')
          ..write('removedAt: $removedAt, ')
          ..write('addedBy: $addedBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GroupSenderKeysTable extends GroupSenderKeys
    with TableInfo<$GroupSenderKeysTable, GroupSenderKey> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GroupSenderKeysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerPeerIdMeta = const VerificationMeta(
    'ownerPeerId',
  );
  @override
  late final GeneratedColumn<String> ownerPeerId = GeneratedColumn<String>(
    'owner_peer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chainKeyMeta = const VerificationMeta(
    'chainKey',
  );
  @override
  late final GeneratedColumn<String> chainKey = GeneratedColumn<String>(
    'chain_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _counterMeta = const VerificationMeta(
    'counter',
  );
  @override
  late final GeneratedColumn<int> counter = GeneratedColumn<int>(
    'counter',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isMineMeta = const VerificationMeta('isMine');
  @override
  late final GeneratedColumn<bool> isMine = GeneratedColumn<bool>(
    'is_mine',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_mine" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    groupId,
    ownerPeerId,
    chainKey,
    counter,
    isMine,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'group_sender_keys';
  @override
  VerificationContext validateIntegrity(
    Insertable<GroupSenderKey> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('owner_peer_id')) {
      context.handle(
        _ownerPeerIdMeta,
        ownerPeerId.isAcceptableOrUnknown(
          data['owner_peer_id']!,
          _ownerPeerIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerPeerIdMeta);
    }
    if (data.containsKey('chain_key')) {
      context.handle(
        _chainKeyMeta,
        chainKey.isAcceptableOrUnknown(data['chain_key']!, _chainKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_chainKeyMeta);
    }
    if (data.containsKey('counter')) {
      context.handle(
        _counterMeta,
        counter.isAcceptableOrUnknown(data['counter']!, _counterMeta),
      );
    } else if (isInserting) {
      context.missing(_counterMeta);
    }
    if (data.containsKey('is_mine')) {
      context.handle(
        _isMineMeta,
        isMine.isAcceptableOrUnknown(data['is_mine']!, _isMineMeta),
      );
    } else if (isInserting) {
      context.missing(_isMineMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId, ownerPeerId};
  @override
  GroupSenderKey map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GroupSenderKey(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      ownerPeerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_peer_id'],
      )!,
      chainKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chain_key'],
      )!,
      counter: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}counter'],
      )!,
      isMine: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_mine'],
      )!,
    );
  }

  @override
  $GroupSenderKeysTable createAlias(String alias) {
    return $GroupSenderKeysTable(attachedDatabase, alias);
  }
}

class GroupSenderKey extends DataClass implements Insertable<GroupSenderKey> {
  final String groupId;
  final String ownerPeerId;
  final String chainKey;
  final int counter;
  final bool isMine;
  const GroupSenderKey({
    required this.groupId,
    required this.ownerPeerId,
    required this.chainKey,
    required this.counter,
    required this.isMine,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['owner_peer_id'] = Variable<String>(ownerPeerId);
    map['chain_key'] = Variable<String>(chainKey);
    map['counter'] = Variable<int>(counter);
    map['is_mine'] = Variable<bool>(isMine);
    return map;
  }

  GroupSenderKeysCompanion toCompanion(bool nullToAbsent) {
    return GroupSenderKeysCompanion(
      groupId: Value(groupId),
      ownerPeerId: Value(ownerPeerId),
      chainKey: Value(chainKey),
      counter: Value(counter),
      isMine: Value(isMine),
    );
  }

  factory GroupSenderKey.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GroupSenderKey(
      groupId: serializer.fromJson<String>(json['groupId']),
      ownerPeerId: serializer.fromJson<String>(json['ownerPeerId']),
      chainKey: serializer.fromJson<String>(json['chainKey']),
      counter: serializer.fromJson<int>(json['counter']),
      isMine: serializer.fromJson<bool>(json['isMine']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'ownerPeerId': serializer.toJson<String>(ownerPeerId),
      'chainKey': serializer.toJson<String>(chainKey),
      'counter': serializer.toJson<int>(counter),
      'isMine': serializer.toJson<bool>(isMine),
    };
  }

  GroupSenderKey copyWith({
    String? groupId,
    String? ownerPeerId,
    String? chainKey,
    int? counter,
    bool? isMine,
  }) => GroupSenderKey(
    groupId: groupId ?? this.groupId,
    ownerPeerId: ownerPeerId ?? this.ownerPeerId,
    chainKey: chainKey ?? this.chainKey,
    counter: counter ?? this.counter,
    isMine: isMine ?? this.isMine,
  );
  GroupSenderKey copyWithCompanion(GroupSenderKeysCompanion data) {
    return GroupSenderKey(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      ownerPeerId: data.ownerPeerId.present
          ? data.ownerPeerId.value
          : this.ownerPeerId,
      chainKey: data.chainKey.present ? data.chainKey.value : this.chainKey,
      counter: data.counter.present ? data.counter.value : this.counter,
      isMine: data.isMine.present ? data.isMine.value : this.isMine,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GroupSenderKey(')
          ..write('groupId: $groupId, ')
          ..write('ownerPeerId: $ownerPeerId, ')
          ..write('chainKey: $chainKey, ')
          ..write('counter: $counter, ')
          ..write('isMine: $isMine')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(groupId, ownerPeerId, chainKey, counter, isMine);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GroupSenderKey &&
          other.groupId == this.groupId &&
          other.ownerPeerId == this.ownerPeerId &&
          other.chainKey == this.chainKey &&
          other.counter == this.counter &&
          other.isMine == this.isMine);
}

class GroupSenderKeysCompanion extends UpdateCompanion<GroupSenderKey> {
  final Value<String> groupId;
  final Value<String> ownerPeerId;
  final Value<String> chainKey;
  final Value<int> counter;
  final Value<bool> isMine;
  final Value<int> rowid;
  const GroupSenderKeysCompanion({
    this.groupId = const Value.absent(),
    this.ownerPeerId = const Value.absent(),
    this.chainKey = const Value.absent(),
    this.counter = const Value.absent(),
    this.isMine = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GroupSenderKeysCompanion.insert({
    required String groupId,
    required String ownerPeerId,
    required String chainKey,
    required int counter,
    required bool isMine,
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       ownerPeerId = Value(ownerPeerId),
       chainKey = Value(chainKey),
       counter = Value(counter),
       isMine = Value(isMine);
  static Insertable<GroupSenderKey> custom({
    Expression<String>? groupId,
    Expression<String>? ownerPeerId,
    Expression<String>? chainKey,
    Expression<int>? counter,
    Expression<bool>? isMine,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (ownerPeerId != null) 'owner_peer_id': ownerPeerId,
      if (chainKey != null) 'chain_key': chainKey,
      if (counter != null) 'counter': counter,
      if (isMine != null) 'is_mine': isMine,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GroupSenderKeysCompanion copyWith({
    Value<String>? groupId,
    Value<String>? ownerPeerId,
    Value<String>? chainKey,
    Value<int>? counter,
    Value<bool>? isMine,
    Value<int>? rowid,
  }) {
    return GroupSenderKeysCompanion(
      groupId: groupId ?? this.groupId,
      ownerPeerId: ownerPeerId ?? this.ownerPeerId,
      chainKey: chainKey ?? this.chainKey,
      counter: counter ?? this.counter,
      isMine: isMine ?? this.isMine,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (ownerPeerId.present) {
      map['owner_peer_id'] = Variable<String>(ownerPeerId.value);
    }
    if (chainKey.present) {
      map['chain_key'] = Variable<String>(chainKey.value);
    }
    if (counter.present) {
      map['counter'] = Variable<int>(counter.value);
    }
    if (isMine.present) {
      map['is_mine'] = Variable<bool>(isMine.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GroupSenderKeysCompanion(')
          ..write('groupId: $groupId, ')
          ..write('ownerPeerId: $ownerPeerId, ')
          ..write('chainKey: $chainKey, ')
          ..write('counter: $counter, ')
          ..write('isMine: $isMine, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MeshStatusesTable extends MeshStatuses
    with TableInfo<$MeshStatusesTable, MeshStatuse> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MeshStatusesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorIdMeta = const VerificationMeta(
    'authorId',
  );
  @override
  late final GeneratedColumn<String> authorId = GeneratedColumn<String>(
    'author_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorPseudoMeta = const VerificationMeta(
    'authorPseudo',
  );
  @override
  late final GeneratedColumn<String> authorPseudo = GeneratedColumn<String>(
    'author_pseudo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<int> expiresAt = GeneratedColumn<int>(
    'expires_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    authorId,
    authorPseudo,
    content,
    createdAt,
    expiresAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mesh_statuses';
  @override
  VerificationContext validateIntegrity(
    Insertable<MeshStatuse> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('author_id')) {
      context.handle(
        _authorIdMeta,
        authorId.isAcceptableOrUnknown(data['author_id']!, _authorIdMeta),
      );
    } else if (isInserting) {
      context.missing(_authorIdMeta);
    }
    if (data.containsKey('author_pseudo')) {
      context.handle(
        _authorPseudoMeta,
        authorPseudo.isAcceptableOrUnknown(
          data['author_pseudo']!,
          _authorPseudoMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_authorPseudoMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MeshStatuse map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MeshStatuse(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      authorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_id'],
      )!,
      authorPseudo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_pseudo'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expires_at'],
      )!,
    );
  }

  @override
  $MeshStatusesTable createAlias(String alias) {
    return $MeshStatusesTable(attachedDatabase, alias);
  }
}

class MeshStatuse extends DataClass implements Insertable<MeshStatuse> {
  final String id;
  final String authorId;
  final String authorPseudo;
  final String content;
  final int createdAt;
  final int expiresAt;
  const MeshStatuse({
    required this.id,
    required this.authorId,
    required this.authorPseudo,
    required this.content,
    required this.createdAt,
    required this.expiresAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['author_id'] = Variable<String>(authorId);
    map['author_pseudo'] = Variable<String>(authorPseudo);
    map['content'] = Variable<String>(content);
    map['created_at'] = Variable<int>(createdAt);
    map['expires_at'] = Variable<int>(expiresAt);
    return map;
  }

  MeshStatusesCompanion toCompanion(bool nullToAbsent) {
    return MeshStatusesCompanion(
      id: Value(id),
      authorId: Value(authorId),
      authorPseudo: Value(authorPseudo),
      content: Value(content),
      createdAt: Value(createdAt),
      expiresAt: Value(expiresAt),
    );
  }

  factory MeshStatuse.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MeshStatuse(
      id: serializer.fromJson<String>(json['id']),
      authorId: serializer.fromJson<String>(json['authorId']),
      authorPseudo: serializer.fromJson<String>(json['authorPseudo']),
      content: serializer.fromJson<String>(json['content']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      expiresAt: serializer.fromJson<int>(json['expiresAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'authorId': serializer.toJson<String>(authorId),
      'authorPseudo': serializer.toJson<String>(authorPseudo),
      'content': serializer.toJson<String>(content),
      'createdAt': serializer.toJson<int>(createdAt),
      'expiresAt': serializer.toJson<int>(expiresAt),
    };
  }

  MeshStatuse copyWith({
    String? id,
    String? authorId,
    String? authorPseudo,
    String? content,
    int? createdAt,
    int? expiresAt,
  }) => MeshStatuse(
    id: id ?? this.id,
    authorId: authorId ?? this.authorId,
    authorPseudo: authorPseudo ?? this.authorPseudo,
    content: content ?? this.content,
    createdAt: createdAt ?? this.createdAt,
    expiresAt: expiresAt ?? this.expiresAt,
  );
  MeshStatuse copyWithCompanion(MeshStatusesCompanion data) {
    return MeshStatuse(
      id: data.id.present ? data.id.value : this.id,
      authorId: data.authorId.present ? data.authorId.value : this.authorId,
      authorPseudo: data.authorPseudo.present
          ? data.authorPseudo.value
          : this.authorPseudo,
      content: data.content.present ? data.content.value : this.content,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MeshStatuse(')
          ..write('id: $id, ')
          ..write('authorId: $authorId, ')
          ..write('authorPseudo: $authorPseudo, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('expiresAt: $expiresAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, authorId, authorPseudo, content, createdAt, expiresAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MeshStatuse &&
          other.id == this.id &&
          other.authorId == this.authorId &&
          other.authorPseudo == this.authorPseudo &&
          other.content == this.content &&
          other.createdAt == this.createdAt &&
          other.expiresAt == this.expiresAt);
}

class MeshStatusesCompanion extends UpdateCompanion<MeshStatuse> {
  final Value<String> id;
  final Value<String> authorId;
  final Value<String> authorPseudo;
  final Value<String> content;
  final Value<int> createdAt;
  final Value<int> expiresAt;
  final Value<int> rowid;
  const MeshStatusesCompanion({
    this.id = const Value.absent(),
    this.authorId = const Value.absent(),
    this.authorPseudo = const Value.absent(),
    this.content = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MeshStatusesCompanion.insert({
    required String id,
    required String authorId,
    required String authorPseudo,
    required String content,
    required int createdAt,
    required int expiresAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       authorId = Value(authorId),
       authorPseudo = Value(authorPseudo),
       content = Value(content),
       createdAt = Value(createdAt),
       expiresAt = Value(expiresAt);
  static Insertable<MeshStatuse> custom({
    Expression<String>? id,
    Expression<String>? authorId,
    Expression<String>? authorPseudo,
    Expression<String>? content,
    Expression<int>? createdAt,
    Expression<int>? expiresAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (authorId != null) 'author_id': authorId,
      if (authorPseudo != null) 'author_pseudo': authorPseudo,
      if (content != null) 'content': content,
      if (createdAt != null) 'created_at': createdAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MeshStatusesCompanion copyWith({
    Value<String>? id,
    Value<String>? authorId,
    Value<String>? authorPseudo,
    Value<String>? content,
    Value<int>? createdAt,
    Value<int>? expiresAt,
    Value<int>? rowid,
  }) {
    return MeshStatusesCompanion(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      authorPseudo: authorPseudo ?? this.authorPseudo,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (authorId.present) {
      map['author_id'] = Variable<String>(authorId.value);
    }
    if (authorPseudo.present) {
      map['author_pseudo'] = Variable<String>(authorPseudo.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<int>(expiresAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MeshStatusesCompanion(')
          ..write('id: $id, ')
          ..write('authorId: $authorId, ')
          ..write('authorPseudo: $authorPseudo, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SeenMessageIdsTable extends SeenMessageIds
    with TableInfo<$SeenMessageIdsTable, SeenMessageId> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SeenMessageIdsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seenAtMeta = const VerificationMeta('seenAt');
  @override
  late final GeneratedColumn<int> seenAt = GeneratedColumn<int>(
    'seen_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [messageId, seenAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'seen_message_ids';
  @override
  VerificationContext validateIntegrity(
    Insertable<SeenMessageId> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('seen_at')) {
      context.handle(
        _seenAtMeta,
        seenAt.isAcceptableOrUnknown(data['seen_at']!, _seenAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {messageId};
  @override
  SeenMessageId map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SeenMessageId(
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      seenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seen_at'],
      ),
    );
  }

  @override
  $SeenMessageIdsTable createAlias(String alias) {
    return $SeenMessageIdsTable(attachedDatabase, alias);
  }
}

class SeenMessageId extends DataClass implements Insertable<SeenMessageId> {
  final String messageId;
  final int? seenAt;
  const SeenMessageId({required this.messageId, this.seenAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['message_id'] = Variable<String>(messageId);
    if (!nullToAbsent || seenAt != null) {
      map['seen_at'] = Variable<int>(seenAt);
    }
    return map;
  }

  SeenMessageIdsCompanion toCompanion(bool nullToAbsent) {
    return SeenMessageIdsCompanion(
      messageId: Value(messageId),
      seenAt: seenAt == null && nullToAbsent
          ? const Value.absent()
          : Value(seenAt),
    );
  }

  factory SeenMessageId.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SeenMessageId(
      messageId: serializer.fromJson<String>(json['messageId']),
      seenAt: serializer.fromJson<int?>(json['seenAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'messageId': serializer.toJson<String>(messageId),
      'seenAt': serializer.toJson<int?>(seenAt),
    };
  }

  SeenMessageId copyWith({
    String? messageId,
    Value<int?> seenAt = const Value.absent(),
  }) => SeenMessageId(
    messageId: messageId ?? this.messageId,
    seenAt: seenAt.present ? seenAt.value : this.seenAt,
  );
  SeenMessageId copyWithCompanion(SeenMessageIdsCompanion data) {
    return SeenMessageId(
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      seenAt: data.seenAt.present ? data.seenAt.value : this.seenAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SeenMessageId(')
          ..write('messageId: $messageId, ')
          ..write('seenAt: $seenAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(messageId, seenAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SeenMessageId &&
          other.messageId == this.messageId &&
          other.seenAt == this.seenAt);
}

class SeenMessageIdsCompanion extends UpdateCompanion<SeenMessageId> {
  final Value<String> messageId;
  final Value<int?> seenAt;
  final Value<int> rowid;
  const SeenMessageIdsCompanion({
    this.messageId = const Value.absent(),
    this.seenAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SeenMessageIdsCompanion.insert({
    required String messageId,
    this.seenAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : messageId = Value(messageId);
  static Insertable<SeenMessageId> custom({
    Expression<String>? messageId,
    Expression<int>? seenAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (messageId != null) 'message_id': messageId,
      if (seenAt != null) 'seen_at': seenAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SeenMessageIdsCompanion copyWith({
    Value<String>? messageId,
    Value<int?>? seenAt,
    Value<int>? rowid,
  }) {
    return SeenMessageIdsCompanion(
      messageId: messageId ?? this.messageId,
      seenAt: seenAt ?? this.seenAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (seenAt.present) {
      map['seen_at'] = Variable<int>(seenAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SeenMessageIdsCompanion(')
          ..write('messageId: $messageId, ')
          ..write('seenAt: $seenAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String value;
  const AppSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(key: Value(key), value: Value(value));
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  AppSetting copyWith({String? key, String? value}) =>
      AppSetting(key: key ?? this.key, value: value ?? this.value);
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $DropletUserTable dropletUser = $DropletUserTable(this);
  late final $MeshMessagesTable meshMessages = $MeshMessagesTable(this);
  late final $MeshGroupsTable meshGroups = $MeshGroupsTable(this);
  late final $GroupMembersTable groupMembers = $GroupMembersTable(this);
  late final $GroupSenderKeysTable groupSenderKeys = $GroupSenderKeysTable(
    this,
  );
  late final $MeshStatusesTable meshStatuses = $MeshStatusesTable(this);
  late final $SeenMessageIdsTable seenMessageIds = $SeenMessageIdsTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    dropletUser,
    meshMessages,
    meshGroups,
    groupMembers,
    groupSenderKeys,
    meshStatuses,
    seenMessageIds,
    appSettings,
  ];
}

typedef $$DropletUserTableCreateCompanionBuilder =
    DropletUserCompanion Function({
      required String id,
      required String pseudo,
      Value<String?> avatarUrl,
      Value<String?> publicKey,
      Value<int> rowid,
    });
typedef $$DropletUserTableUpdateCompanionBuilder =
    DropletUserCompanion Function({
      Value<String> id,
      Value<String> pseudo,
      Value<String?> avatarUrl,
      Value<String?> publicKey,
      Value<int> rowid,
    });

class $$DropletUserTableFilterComposer
    extends Composer<_$AppDatabase, $DropletUserTable> {
  $$DropletUserTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pseudo => $composableBuilder(
    column: $table.pseudo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DropletUserTableOrderingComposer
    extends Composer<_$AppDatabase, $DropletUserTable> {
  $$DropletUserTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pseudo => $composableBuilder(
    column: $table.pseudo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DropletUserTableAnnotationComposer
    extends Composer<_$AppDatabase, $DropletUserTable> {
  $$DropletUserTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get pseudo =>
      $composableBuilder(column: $table.pseudo, builder: (column) => column);

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);

  GeneratedColumn<String> get publicKey =>
      $composableBuilder(column: $table.publicKey, builder: (column) => column);
}

class $$DropletUserTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DropletUserTable,
          DropletUserData,
          $$DropletUserTableFilterComposer,
          $$DropletUserTableOrderingComposer,
          $$DropletUserTableAnnotationComposer,
          $$DropletUserTableCreateCompanionBuilder,
          $$DropletUserTableUpdateCompanionBuilder,
          (
            DropletUserData,
            BaseReferences<_$AppDatabase, $DropletUserTable, DropletUserData>,
          ),
          DropletUserData,
          PrefetchHooks Function()
        > {
  $$DropletUserTableTableManager(_$AppDatabase db, $DropletUserTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DropletUserTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DropletUserTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DropletUserTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> pseudo = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> publicKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DropletUserCompanion(
                id: id,
                pseudo: pseudo,
                avatarUrl: avatarUrl,
                publicKey: publicKey,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String pseudo,
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> publicKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DropletUserCompanion.insert(
                id: id,
                pseudo: pseudo,
                avatarUrl: avatarUrl,
                publicKey: publicKey,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DropletUserTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DropletUserTable,
      DropletUserData,
      $$DropletUserTableFilterComposer,
      $$DropletUserTableOrderingComposer,
      $$DropletUserTableAnnotationComposer,
      $$DropletUserTableCreateCompanionBuilder,
      $$DropletUserTableUpdateCompanionBuilder,
      (
        DropletUserData,
        BaseReferences<_$AppDatabase, $DropletUserTable, DropletUserData>,
      ),
      DropletUserData,
      PrefetchHooks Function()
    >;
typedef $$MeshMessagesTableCreateCompanionBuilder =
    MeshMessagesCompanion Function({
      required String id,
      required String authorPseudo,
      required String content,
      required String type,
      required int timestamp,
      Value<String?> senderId,
      Value<String?> targetId,
      Value<String?> imageUrl,
      Value<String?> audioUrl,
      required int hopCount,
      required String reactions,
      required int updatedAt,
      required String syncStatus,
      Value<String?> fileId,
      Value<String?> fileName,
      Value<int?> fileSize,
      Value<String?> fileMimeType,
      Value<String?> replyToId,
      required String status,
      Value<String?> routeInfo,
      Value<int?> readAt,
      Value<String?> groupId,
      Value<int> rowid,
    });
typedef $$MeshMessagesTableUpdateCompanionBuilder =
    MeshMessagesCompanion Function({
      Value<String> id,
      Value<String> authorPseudo,
      Value<String> content,
      Value<String> type,
      Value<int> timestamp,
      Value<String?> senderId,
      Value<String?> targetId,
      Value<String?> imageUrl,
      Value<String?> audioUrl,
      Value<int> hopCount,
      Value<String> reactions,
      Value<int> updatedAt,
      Value<String> syncStatus,
      Value<String?> fileId,
      Value<String?> fileName,
      Value<int?> fileSize,
      Value<String?> fileMimeType,
      Value<String?> replyToId,
      Value<String> status,
      Value<String?> routeInfo,
      Value<int?> readAt,
      Value<String?> groupId,
      Value<int> rowid,
    });

class $$MeshMessagesTableFilterComposer
    extends Composer<_$AppDatabase, $MeshMessagesTable> {
  $$MeshMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorPseudo => $composableBuilder(
    column: $table.authorPseudo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get audioUrl => $composableBuilder(
    column: $table.audioUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hopCount => $composableBuilder(
    column: $table.hopCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reactions => $composableBuilder(
    column: $table.reactions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileMimeType => $composableBuilder(
    column: $table.fileMimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyToId => $composableBuilder(
    column: $table.replyToId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get routeInfo => $composableBuilder(
    column: $table.routeInfo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get readAt => $composableBuilder(
    column: $table.readAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MeshMessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $MeshMessagesTable> {
  $$MeshMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorPseudo => $composableBuilder(
    column: $table.authorPseudo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioUrl => $composableBuilder(
    column: $table.audioUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hopCount => $composableBuilder(
    column: $table.hopCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reactions => $composableBuilder(
    column: $table.reactions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileMimeType => $composableBuilder(
    column: $table.fileMimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyToId => $composableBuilder(
    column: $table.replyToId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get routeInfo => $composableBuilder(
    column: $table.routeInfo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get readAt => $composableBuilder(
    column: $table.readAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MeshMessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MeshMessagesTable> {
  $$MeshMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get authorPseudo => $composableBuilder(
    column: $table.authorPseudo,
    builder: (column) => column,
  );

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<String> get senderId =>
      $composableBuilder(column: $table.senderId, builder: (column) => column);

  GeneratedColumn<String> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<String> get audioUrl =>
      $composableBuilder(column: $table.audioUrl, builder: (column) => column);

  GeneratedColumn<int> get hopCount =>
      $composableBuilder(column: $table.hopCount, builder: (column) => column);

  GeneratedColumn<String> get reactions =>
      $composableBuilder(column: $table.reactions, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fileId =>
      $composableBuilder(column: $table.fileId, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<String> get fileMimeType => $composableBuilder(
    column: $table.fileMimeType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get replyToId =>
      $composableBuilder(column: $table.replyToId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get routeInfo =>
      $composableBuilder(column: $table.routeInfo, builder: (column) => column);

  GeneratedColumn<int> get readAt =>
      $composableBuilder(column: $table.readAt, builder: (column) => column);

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);
}

class $$MeshMessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MeshMessagesTable,
          MeshMessage,
          $$MeshMessagesTableFilterComposer,
          $$MeshMessagesTableOrderingComposer,
          $$MeshMessagesTableAnnotationComposer,
          $$MeshMessagesTableCreateCompanionBuilder,
          $$MeshMessagesTableUpdateCompanionBuilder,
          (
            MeshMessage,
            BaseReferences<_$AppDatabase, $MeshMessagesTable, MeshMessage>,
          ),
          MeshMessage,
          PrefetchHooks Function()
        > {
  $$MeshMessagesTableTableManager(_$AppDatabase db, $MeshMessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MeshMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MeshMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MeshMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> authorPseudo = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int> timestamp = const Value.absent(),
                Value<String?> senderId = const Value.absent(),
                Value<String?> targetId = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
                Value<String?> audioUrl = const Value.absent(),
                Value<int> hopCount = const Value.absent(),
                Value<String> reactions = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<String?> fileId = const Value.absent(),
                Value<String?> fileName = const Value.absent(),
                Value<int?> fileSize = const Value.absent(),
                Value<String?> fileMimeType = const Value.absent(),
                Value<String?> replyToId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> routeInfo = const Value.absent(),
                Value<int?> readAt = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MeshMessagesCompanion(
                id: id,
                authorPseudo: authorPseudo,
                content: content,
                type: type,
                timestamp: timestamp,
                senderId: senderId,
                targetId: targetId,
                imageUrl: imageUrl,
                audioUrl: audioUrl,
                hopCount: hopCount,
                reactions: reactions,
                updatedAt: updatedAt,
                syncStatus: syncStatus,
                fileId: fileId,
                fileName: fileName,
                fileSize: fileSize,
                fileMimeType: fileMimeType,
                replyToId: replyToId,
                status: status,
                routeInfo: routeInfo,
                readAt: readAt,
                groupId: groupId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String authorPseudo,
                required String content,
                required String type,
                required int timestamp,
                Value<String?> senderId = const Value.absent(),
                Value<String?> targetId = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
                Value<String?> audioUrl = const Value.absent(),
                required int hopCount,
                required String reactions,
                required int updatedAt,
                required String syncStatus,
                Value<String?> fileId = const Value.absent(),
                Value<String?> fileName = const Value.absent(),
                Value<int?> fileSize = const Value.absent(),
                Value<String?> fileMimeType = const Value.absent(),
                Value<String?> replyToId = const Value.absent(),
                required String status,
                Value<String?> routeInfo = const Value.absent(),
                Value<int?> readAt = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MeshMessagesCompanion.insert(
                id: id,
                authorPseudo: authorPseudo,
                content: content,
                type: type,
                timestamp: timestamp,
                senderId: senderId,
                targetId: targetId,
                imageUrl: imageUrl,
                audioUrl: audioUrl,
                hopCount: hopCount,
                reactions: reactions,
                updatedAt: updatedAt,
                syncStatus: syncStatus,
                fileId: fileId,
                fileName: fileName,
                fileSize: fileSize,
                fileMimeType: fileMimeType,
                replyToId: replyToId,
                status: status,
                routeInfo: routeInfo,
                readAt: readAt,
                groupId: groupId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MeshMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MeshMessagesTable,
      MeshMessage,
      $$MeshMessagesTableFilterComposer,
      $$MeshMessagesTableOrderingComposer,
      $$MeshMessagesTableAnnotationComposer,
      $$MeshMessagesTableCreateCompanionBuilder,
      $$MeshMessagesTableUpdateCompanionBuilder,
      (
        MeshMessage,
        BaseReferences<_$AppDatabase, $MeshMessagesTable, MeshMessage>,
      ),
      MeshMessage,
      PrefetchHooks Function()
    >;
typedef $$MeshGroupsTableCreateCompanionBuilder =
    MeshGroupsCompanion Function({
      required String id,
      required String name,
      Value<String?> avatarUrl,
      required String createdBy,
      required int createdAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$MeshGroupsTableUpdateCompanionBuilder =
    MeshGroupsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> avatarUrl,
      Value<String> createdBy,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$MeshGroupsTableFilterComposer
    extends Composer<_$AppDatabase, $MeshGroupsTable> {
  $$MeshGroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MeshGroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $MeshGroupsTable> {
  $$MeshGroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MeshGroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MeshGroupsTable> {
  $$MeshGroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);

  GeneratedColumn<String> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$MeshGroupsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MeshGroupsTable,
          MeshGroup,
          $$MeshGroupsTableFilterComposer,
          $$MeshGroupsTableOrderingComposer,
          $$MeshGroupsTableAnnotationComposer,
          $$MeshGroupsTableCreateCompanionBuilder,
          $$MeshGroupsTableUpdateCompanionBuilder,
          (
            MeshGroup,
            BaseReferences<_$AppDatabase, $MeshGroupsTable, MeshGroup>,
          ),
          MeshGroup,
          PrefetchHooks Function()
        > {
  $$MeshGroupsTableTableManager(_$AppDatabase db, $MeshGroupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MeshGroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MeshGroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MeshGroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<String> createdBy = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MeshGroupsCompanion(
                id: id,
                name: name,
                avatarUrl: avatarUrl,
                createdBy: createdBy,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> avatarUrl = const Value.absent(),
                required String createdBy,
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => MeshGroupsCompanion.insert(
                id: id,
                name: name,
                avatarUrl: avatarUrl,
                createdBy: createdBy,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MeshGroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MeshGroupsTable,
      MeshGroup,
      $$MeshGroupsTableFilterComposer,
      $$MeshGroupsTableOrderingComposer,
      $$MeshGroupsTableAnnotationComposer,
      $$MeshGroupsTableCreateCompanionBuilder,
      $$MeshGroupsTableUpdateCompanionBuilder,
      (MeshGroup, BaseReferences<_$AppDatabase, $MeshGroupsTable, MeshGroup>),
      MeshGroup,
      PrefetchHooks Function()
    >;
typedef $$GroupMembersTableCreateCompanionBuilder =
    GroupMembersCompanion Function({
      required String groupId,
      required String peerId,
      required String role,
      required int addedAt,
      Value<int?> removedAt,
      required String addedBy,
      Value<int> rowid,
    });
typedef $$GroupMembersTableUpdateCompanionBuilder =
    GroupMembersCompanion Function({
      Value<String> groupId,
      Value<String> peerId,
      Value<String> role,
      Value<int> addedAt,
      Value<int?> removedAt,
      Value<String> addedBy,
      Value<int> rowid,
    });

class $$GroupMembersTableFilterComposer
    extends Composer<_$AppDatabase, $GroupMembersTable> {
  $$GroupMembersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get removedAt => $composableBuilder(
    column: $table.removedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get addedBy => $composableBuilder(
    column: $table.addedBy,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GroupMembersTableOrderingComposer
    extends Composer<_$AppDatabase, $GroupMembersTable> {
  $$GroupMembersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get removedAt => $composableBuilder(
    column: $table.removedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get addedBy => $composableBuilder(
    column: $table.addedBy,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GroupMembersTableAnnotationComposer
    extends Composer<_$AppDatabase, $GroupMembersTable> {
  $$GroupMembersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get peerId =>
      $composableBuilder(column: $table.peerId, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<int> get removedAt =>
      $composableBuilder(column: $table.removedAt, builder: (column) => column);

  GeneratedColumn<String> get addedBy =>
      $composableBuilder(column: $table.addedBy, builder: (column) => column);
}

class $$GroupMembersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GroupMembersTable,
          GroupMember,
          $$GroupMembersTableFilterComposer,
          $$GroupMembersTableOrderingComposer,
          $$GroupMembersTableAnnotationComposer,
          $$GroupMembersTableCreateCompanionBuilder,
          $$GroupMembersTableUpdateCompanionBuilder,
          (
            GroupMember,
            BaseReferences<_$AppDatabase, $GroupMembersTable, GroupMember>,
          ),
          GroupMember,
          PrefetchHooks Function()
        > {
  $$GroupMembersTableTableManager(_$AppDatabase db, $GroupMembersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GroupMembersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GroupMembersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GroupMembersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<String> peerId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<int> addedAt = const Value.absent(),
                Value<int?> removedAt = const Value.absent(),
                Value<String> addedBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GroupMembersCompanion(
                groupId: groupId,
                peerId: peerId,
                role: role,
                addedAt: addedAt,
                removedAt: removedAt,
                addedBy: addedBy,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required String peerId,
                required String role,
                required int addedAt,
                Value<int?> removedAt = const Value.absent(),
                required String addedBy,
                Value<int> rowid = const Value.absent(),
              }) => GroupMembersCompanion.insert(
                groupId: groupId,
                peerId: peerId,
                role: role,
                addedAt: addedAt,
                removedAt: removedAt,
                addedBy: addedBy,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GroupMembersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GroupMembersTable,
      GroupMember,
      $$GroupMembersTableFilterComposer,
      $$GroupMembersTableOrderingComposer,
      $$GroupMembersTableAnnotationComposer,
      $$GroupMembersTableCreateCompanionBuilder,
      $$GroupMembersTableUpdateCompanionBuilder,
      (
        GroupMember,
        BaseReferences<_$AppDatabase, $GroupMembersTable, GroupMember>,
      ),
      GroupMember,
      PrefetchHooks Function()
    >;
typedef $$GroupSenderKeysTableCreateCompanionBuilder =
    GroupSenderKeysCompanion Function({
      required String groupId,
      required String ownerPeerId,
      required String chainKey,
      required int counter,
      required bool isMine,
      Value<int> rowid,
    });
typedef $$GroupSenderKeysTableUpdateCompanionBuilder =
    GroupSenderKeysCompanion Function({
      Value<String> groupId,
      Value<String> ownerPeerId,
      Value<String> chainKey,
      Value<int> counter,
      Value<bool> isMine,
      Value<int> rowid,
    });

class $$GroupSenderKeysTableFilterComposer
    extends Composer<_$AppDatabase, $GroupSenderKeysTable> {
  $$GroupSenderKeysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerPeerId => $composableBuilder(
    column: $table.ownerPeerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chainKey => $composableBuilder(
    column: $table.chainKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get counter => $composableBuilder(
    column: $table.counter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isMine => $composableBuilder(
    column: $table.isMine,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GroupSenderKeysTableOrderingComposer
    extends Composer<_$AppDatabase, $GroupSenderKeysTable> {
  $$GroupSenderKeysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerPeerId => $composableBuilder(
    column: $table.ownerPeerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chainKey => $composableBuilder(
    column: $table.chainKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get counter => $composableBuilder(
    column: $table.counter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isMine => $composableBuilder(
    column: $table.isMine,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GroupSenderKeysTableAnnotationComposer
    extends Composer<_$AppDatabase, $GroupSenderKeysTable> {
  $$GroupSenderKeysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get ownerPeerId => $composableBuilder(
    column: $table.ownerPeerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get chainKey =>
      $composableBuilder(column: $table.chainKey, builder: (column) => column);

  GeneratedColumn<int> get counter =>
      $composableBuilder(column: $table.counter, builder: (column) => column);

  GeneratedColumn<bool> get isMine =>
      $composableBuilder(column: $table.isMine, builder: (column) => column);
}

class $$GroupSenderKeysTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GroupSenderKeysTable,
          GroupSenderKey,
          $$GroupSenderKeysTableFilterComposer,
          $$GroupSenderKeysTableOrderingComposer,
          $$GroupSenderKeysTableAnnotationComposer,
          $$GroupSenderKeysTableCreateCompanionBuilder,
          $$GroupSenderKeysTableUpdateCompanionBuilder,
          (
            GroupSenderKey,
            BaseReferences<
              _$AppDatabase,
              $GroupSenderKeysTable,
              GroupSenderKey
            >,
          ),
          GroupSenderKey,
          PrefetchHooks Function()
        > {
  $$GroupSenderKeysTableTableManager(
    _$AppDatabase db,
    $GroupSenderKeysTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GroupSenderKeysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GroupSenderKeysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GroupSenderKeysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<String> ownerPeerId = const Value.absent(),
                Value<String> chainKey = const Value.absent(),
                Value<int> counter = const Value.absent(),
                Value<bool> isMine = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GroupSenderKeysCompanion(
                groupId: groupId,
                ownerPeerId: ownerPeerId,
                chainKey: chainKey,
                counter: counter,
                isMine: isMine,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required String ownerPeerId,
                required String chainKey,
                required int counter,
                required bool isMine,
                Value<int> rowid = const Value.absent(),
              }) => GroupSenderKeysCompanion.insert(
                groupId: groupId,
                ownerPeerId: ownerPeerId,
                chainKey: chainKey,
                counter: counter,
                isMine: isMine,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GroupSenderKeysTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GroupSenderKeysTable,
      GroupSenderKey,
      $$GroupSenderKeysTableFilterComposer,
      $$GroupSenderKeysTableOrderingComposer,
      $$GroupSenderKeysTableAnnotationComposer,
      $$GroupSenderKeysTableCreateCompanionBuilder,
      $$GroupSenderKeysTableUpdateCompanionBuilder,
      (
        GroupSenderKey,
        BaseReferences<_$AppDatabase, $GroupSenderKeysTable, GroupSenderKey>,
      ),
      GroupSenderKey,
      PrefetchHooks Function()
    >;
typedef $$MeshStatusesTableCreateCompanionBuilder =
    MeshStatusesCompanion Function({
      required String id,
      required String authorId,
      required String authorPseudo,
      required String content,
      required int createdAt,
      required int expiresAt,
      Value<int> rowid,
    });
typedef $$MeshStatusesTableUpdateCompanionBuilder =
    MeshStatusesCompanion Function({
      Value<String> id,
      Value<String> authorId,
      Value<String> authorPseudo,
      Value<String> content,
      Value<int> createdAt,
      Value<int> expiresAt,
      Value<int> rowid,
    });

class $$MeshStatusesTableFilterComposer
    extends Composer<_$AppDatabase, $MeshStatusesTable> {
  $$MeshStatusesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorId => $composableBuilder(
    column: $table.authorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorPseudo => $composableBuilder(
    column: $table.authorPseudo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MeshStatusesTableOrderingComposer
    extends Composer<_$AppDatabase, $MeshStatusesTable> {
  $$MeshStatusesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorId => $composableBuilder(
    column: $table.authorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorPseudo => $composableBuilder(
    column: $table.authorPseudo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MeshStatusesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MeshStatusesTable> {
  $$MeshStatusesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get authorId =>
      $composableBuilder(column: $table.authorId, builder: (column) => column);

  GeneratedColumn<String> get authorPseudo => $composableBuilder(
    column: $table.authorPseudo,
    builder: (column) => column,
  );

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);
}

class $$MeshStatusesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MeshStatusesTable,
          MeshStatuse,
          $$MeshStatusesTableFilterComposer,
          $$MeshStatusesTableOrderingComposer,
          $$MeshStatusesTableAnnotationComposer,
          $$MeshStatusesTableCreateCompanionBuilder,
          $$MeshStatusesTableUpdateCompanionBuilder,
          (
            MeshStatuse,
            BaseReferences<_$AppDatabase, $MeshStatusesTable, MeshStatuse>,
          ),
          MeshStatuse,
          PrefetchHooks Function()
        > {
  $$MeshStatusesTableTableManager(_$AppDatabase db, $MeshStatusesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MeshStatusesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MeshStatusesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MeshStatusesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> authorId = const Value.absent(),
                Value<String> authorPseudo = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> expiresAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MeshStatusesCompanion(
                id: id,
                authorId: authorId,
                authorPseudo: authorPseudo,
                content: content,
                createdAt: createdAt,
                expiresAt: expiresAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String authorId,
                required String authorPseudo,
                required String content,
                required int createdAt,
                required int expiresAt,
                Value<int> rowid = const Value.absent(),
              }) => MeshStatusesCompanion.insert(
                id: id,
                authorId: authorId,
                authorPseudo: authorPseudo,
                content: content,
                createdAt: createdAt,
                expiresAt: expiresAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MeshStatusesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MeshStatusesTable,
      MeshStatuse,
      $$MeshStatusesTableFilterComposer,
      $$MeshStatusesTableOrderingComposer,
      $$MeshStatusesTableAnnotationComposer,
      $$MeshStatusesTableCreateCompanionBuilder,
      $$MeshStatusesTableUpdateCompanionBuilder,
      (
        MeshStatuse,
        BaseReferences<_$AppDatabase, $MeshStatusesTable, MeshStatuse>,
      ),
      MeshStatuse,
      PrefetchHooks Function()
    >;
typedef $$SeenMessageIdsTableCreateCompanionBuilder =
    SeenMessageIdsCompanion Function({
      required String messageId,
      Value<int?> seenAt,
      Value<int> rowid,
    });
typedef $$SeenMessageIdsTableUpdateCompanionBuilder =
    SeenMessageIdsCompanion Function({
      Value<String> messageId,
      Value<int?> seenAt,
      Value<int> rowid,
    });

class $$SeenMessageIdsTableFilterComposer
    extends Composer<_$AppDatabase, $SeenMessageIdsTable> {
  $$SeenMessageIdsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seenAt => $composableBuilder(
    column: $table.seenAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SeenMessageIdsTableOrderingComposer
    extends Composer<_$AppDatabase, $SeenMessageIdsTable> {
  $$SeenMessageIdsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seenAt => $composableBuilder(
    column: $table.seenAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SeenMessageIdsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SeenMessageIdsTable> {
  $$SeenMessageIdsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<int> get seenAt =>
      $composableBuilder(column: $table.seenAt, builder: (column) => column);
}

class $$SeenMessageIdsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SeenMessageIdsTable,
          SeenMessageId,
          $$SeenMessageIdsTableFilterComposer,
          $$SeenMessageIdsTableOrderingComposer,
          $$SeenMessageIdsTableAnnotationComposer,
          $$SeenMessageIdsTableCreateCompanionBuilder,
          $$SeenMessageIdsTableUpdateCompanionBuilder,
          (
            SeenMessageId,
            BaseReferences<_$AppDatabase, $SeenMessageIdsTable, SeenMessageId>,
          ),
          SeenMessageId,
          PrefetchHooks Function()
        > {
  $$SeenMessageIdsTableTableManager(
    _$AppDatabase db,
    $SeenMessageIdsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SeenMessageIdsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SeenMessageIdsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SeenMessageIdsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> messageId = const Value.absent(),
                Value<int?> seenAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SeenMessageIdsCompanion(
                messageId: messageId,
                seenAt: seenAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String messageId,
                Value<int?> seenAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SeenMessageIdsCompanion.insert(
                messageId: messageId,
                seenAt: seenAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SeenMessageIdsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SeenMessageIdsTable,
      SeenMessageId,
      $$SeenMessageIdsTableFilterComposer,
      $$SeenMessageIdsTableOrderingComposer,
      $$SeenMessageIdsTableAnnotationComposer,
      $$SeenMessageIdsTableCreateCompanionBuilder,
      $$SeenMessageIdsTableUpdateCompanionBuilder,
      (
        SeenMessageId,
        BaseReferences<_$AppDatabase, $SeenMessageIdsTable, SeenMessageId>,
      ),
      SeenMessageId,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$DropletUserTableTableManager get dropletUser =>
      $$DropletUserTableTableManager(_db, _db.dropletUser);
  $$MeshMessagesTableTableManager get meshMessages =>
      $$MeshMessagesTableTableManager(_db, _db.meshMessages);
  $$MeshGroupsTableTableManager get meshGroups =>
      $$MeshGroupsTableTableManager(_db, _db.meshGroups);
  $$GroupMembersTableTableManager get groupMembers =>
      $$GroupMembersTableTableManager(_db, _db.groupMembers);
  $$GroupSenderKeysTableTableManager get groupSenderKeys =>
      $$GroupSenderKeysTableTableManager(_db, _db.groupSenderKeys);
  $$MeshStatusesTableTableManager get meshStatuses =>
      $$MeshStatusesTableTableManager(_db, _db.meshStatuses);
  $$SeenMessageIdsTableTableManager get seenMessageIds =>
      $$SeenMessageIdsTableTableManager(_db, _db.seenMessageIds);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
}
