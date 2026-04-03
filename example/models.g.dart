// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// RelaxTableGenerator
// **************************************************************************

// Schema for User
final userSchema = TableSchema<User>(
  tableName: 'users',
  columns: [
    ColumnDef.text('id', isPrimaryKey: true),
    ColumnDef.text('name'),
    ColumnDef.integer('age'),
    ColumnDef.boolean('active'),
    ColumnDef.dateTime('created_at'),
  ],
  fromMap: (map) => User(
    id: map['id'] as String,
    name: map['name'] as String,
    age: map['age'] as int,
    active: map['active'] as bool,
    createdAt: map['created_at'] as DateTime,
  ),
  toMap: (entity) => {
    'id': entity.id,
    'name': entity.name,
    'age': entity.age,
    'active': entity.active,
    'created_at': entity.createdAt,
  },
);

// Schema for Post
final postSchema = TableSchema<Post>(
  tableName: 'blog_posts',
  columns: [
    ColumnDef.text('id', isPrimaryKey: true),
    ColumnDef.text('title'),
    ColumnDef.text('body'),
    ColumnDef.text('author_id'),
    ColumnDef.dateTime('published_at'),
    ColumnDef.boolean('is_draft'),
  ],
  fromMap: (map) => Post(
    id: map['id'] as String,
    title: map['title'] as String,
    body: map['body'] as String,
    authorId: map['author_id'] as String,
    publishedAt: map['published_at'] as DateTime,
    isDraft: map['is_draft'] as bool,
  ),
  toMap: (entity) => {
    'id': entity.id,
    'title': entity.title,
    'body': entity.body,
    'author_id': entity.authorId,
    'published_at': entity.publishedAt,
    'is_draft': entity.isDraft,
  },
);
