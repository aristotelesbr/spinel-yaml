/* sp_yaml.c -- the bridge between libyaml and yaml.rb.

   libyaml reads the text and reports it as events (a mapping starts, a
   scalar, an alias, ...), and writes text from the same kind of events.
   This file translates between those events and one flat Ruby Array with
   EVENT_FIELDS slots per event, in both directions, and decides nothing:
   typing scalars, building Hashes and Arrays, aliases, merge keys, the
   safe_load rules and the style of dumped scalars are all in yaml.rb.
   Keeping the C to a translation keeps every hash key possible (the
   package ABI only builds String-keyed hashes) and the behaviour readable
   in one place.

   Parsed events (spinel_yaml_events): type, value, anchor, tag, quoted,
   style, line, column. type is libyaml's yaml_event_type_t, or EVENT_ERROR
   for a parse error, in which case value is the problem, anchor the
   context, quoted the problem offset and line/column the context mark --
   the fields Psych's SyntaxError is built from. Strings carry their byte
   length, so a scalar holding "\0" survives.

   Events to emit (spinel_yaml_emit): type, value, anchor, tag, plain,
   quoted, style, implicit -- the arguments of libyaml's event
   initializers, with an alias's anchor in value and a document's
   "major.minor" version directive in value. */
#include "spinel/runtime.h"
#include "yaml.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#define EVENT_FIELDS 8
#define EVENT_ERROR -1

static void push_int(sp_PolyArray *a, sp_int i) { sp_PolyArray_push(a, sp_box_int(i)); }

static void push_bytes(sp_PolyArray *a, const unsigned char *bytes, size_t len) {
  if (!bytes) {
    sp_PolyArray_push(a, sp_box_nil());
    return;
  }
  char *s = sp_str_alloc_raw(len + 1);
  memcpy(s, bytes, len);
  s[len] = '\0';
  sp_str_set_len(s, len);
  SP_GC_ROOT_STR(s);
  sp_PolyArray_push(a, sp_box_str(s));
}

static void push_cstr(sp_PolyArray *a, const char *s) {
  push_bytes(a, (const unsigned char *)s, s ? strlen(s) : 0);
}

static void push_event(sp_PolyArray *a, yaml_event_t *e) {
  const unsigned char *value = NULL, *anchor = NULL, *tag = NULL;
  size_t value_len = 0;
  sp_int quoted = 0, style = 0;
  switch (e->type) {
  case YAML_ALIAS_EVENT:
    value = e->data.alias.anchor;
    value_len = value ? strlen((const char *)value) : 0;
    break;
  case YAML_SCALAR_EVENT:
    value = e->data.scalar.value;
    value_len = e->data.scalar.length;
    anchor = e->data.scalar.anchor;
    tag = e->data.scalar.tag;
    quoted = e->data.scalar.quoted_implicit;
    style = e->data.scalar.style;
    break;
  case YAML_SEQUENCE_START_EVENT:
    anchor = e->data.sequence_start.anchor;
    tag = e->data.sequence_start.tag;
    style = e->data.sequence_start.style;
    break;
  case YAML_MAPPING_START_EVENT:
    anchor = e->data.mapping_start.anchor;
    tag = e->data.mapping_start.tag;
    style = e->data.mapping_start.style;
    break;
  default:
    break;
  }
  push_int(a, e->type);
  push_bytes(a, value, value_len);
  push_cstr(a, (const char *)anchor);
  push_cstr(a, (const char *)tag);
  push_int(a, quoted);
  push_int(a, style);
  push_int(a, (sp_int)e->start_mark.line + 1);
  push_int(a, (sp_int)e->start_mark.column + 1);
}

static void push_error(sp_PolyArray *a, yaml_parser_t *p) {
  push_int(a, EVENT_ERROR);
  push_cstr(a, p->problem);
  push_cstr(a, p->context);
  push_cstr(a, NULL);
  push_int(a, (sp_int)p->problem_offset);
  push_int(a, 0);
  push_int(a, (sp_int)p->context_mark.line + 1);
  push_int(a, (sp_int)p->context_mark.column + 1);
}

/* The events of text, up to the end of its first document, or of every
   document when all_documents is nonzero. A parse error ends the list with
   an EVENT_ERROR record. */
sp_RbVal spinel_yaml_events(const char *text, sp_int all_documents) {
  SP_GC_ROOT_STR(text);
  sp_RbVal box = sp_box_poly_array(sp_PolyArray_new());
  SP_GC_ROOT_RBVAL(box);
  sp_PolyArray *events = (sp_PolyArray *)box.v.p;

  yaml_parser_t parser;
  if (!yaml_parser_initialize(&parser)) sp_oom_die();
  yaml_parser_set_input_string(&parser, (const unsigned char *)text, strlen(text));

  for (;;) {
    yaml_event_t event;
    if (!yaml_parser_parse(&parser, &event)) {
      if (parser.error == YAML_MEMORY_ERROR) sp_oom_die();
      push_error(events, &parser);
      break;
    }
    push_event(events, &event);
    yaml_event_type_t type = event.type;
    yaml_event_delete(&event);
    if (type == YAML_STREAM_END_EVENT) break;
    if (type == YAML_DOCUMENT_END_EVENT && !all_documents) break;
  }
  yaml_parser_delete(&parser);
  return box;
}

/* ---------- emitting ---------- */

typedef struct { char *p; size_t len, cap; } outbuf;

static int write_out(void *data, unsigned char *bytes, size_t size) {
  outbuf *b = (outbuf *)data;
  if (b->len + size + 1 > b->cap) {
    size_t cap = (b->len + size + 1) * 2;
    char *p = realloc(b->p, cap);
    if (!p) return 0;
    b->p = p;
    b->cap = cap;
  }
  memcpy(b->p + b->len, bytes, size);
  b->len += size;
  return 1;
}

static sp_RbVal field(sp_RbVal events, sp_int i) { return sp_json_aref_fn(events, i); }

static const char *field_str(sp_RbVal events, sp_int i) {
  sp_RbVal v = field(events, i);
  return v.tag == SP_TAG_STR ? v.v.s : NULL;
}

static sp_int field_int(sp_RbVal events, sp_int i) {
  sp_RbVal v = field(events, i);
  return v.tag == SP_TAG_INT ? v.v.i : 0;
}

/* The libyaml event for the record at i; 0 when libyaml refuses it. */
static int make_event(yaml_event_t *e, sp_RbVal events, sp_int i) {
  sp_int type = field_int(events, i);
  const yaml_char_t *value = (const yaml_char_t *)field_str(events, i + 1);
  const yaml_char_t *anchor = (const yaml_char_t *)field_str(events, i + 2);
  const yaml_char_t *tag = (const yaml_char_t *)field_str(events, i + 3);
  int plain = (int)field_int(events, i + 4);
  int quoted = (int)field_int(events, i + 5);
  int style = (int)field_int(events, i + 6);
  int implicit = (int)field_int(events, i + 7);
  switch (type) {
  case YAML_STREAM_START_EVENT:
    return yaml_stream_start_event_initialize(e, YAML_UTF8_ENCODING);
  case YAML_STREAM_END_EVENT:
    return yaml_stream_end_event_initialize(e);
  case YAML_DOCUMENT_START_EVENT: {
    yaml_version_directive_t version;
    if (value && sscanf((const char *)value, "%d.%d", &version.major, &version.minor) == 2)
      return yaml_document_start_event_initialize(e, &version, NULL, NULL, implicit);
    return yaml_document_start_event_initialize(e, NULL, NULL, NULL, implicit);
  }
  case YAML_DOCUMENT_END_EVENT:
    return yaml_document_end_event_initialize(e, implicit);
  case YAML_ALIAS_EVENT:
    return yaml_alias_event_initialize(e, value);
  case YAML_SCALAR_EVENT:
    return yaml_scalar_event_initialize(e, anchor, tag, value ? value : (const yaml_char_t *)"",
                                        value ? (int)strlen((const char *)value) : 0,
                                        plain, quoted, (yaml_scalar_style_t)style);
  case YAML_SEQUENCE_START_EVENT:
    return yaml_sequence_start_event_initialize(e, anchor, tag, implicit, (yaml_sequence_style_t)style);
  case YAML_SEQUENCE_END_EVENT:
    return yaml_sequence_end_event_initialize(e);
  case YAML_MAPPING_START_EVENT:
    return yaml_mapping_start_event_initialize(e, anchor, tag, implicit, (yaml_mapping_style_t)style);
  case YAML_MAPPING_END_EVENT:
    return yaml_mapping_end_event_initialize(e);
  default:
    return 0;
  }
}

/* The text libyaml's emitter writes for events, set up as Psych's emitter
   is: unicode output, then the line width, indentation and canonical form
   (0, 2 and 0 are libyaml's own defaults; a width of -1 is unlimited). */
const char *spinel_yaml_emit(sp_RbVal events, sp_int width, sp_int indent, sp_int canonical) {
  SP_GC_ROOT_RBVAL(events);
  yaml_emitter_t emitter;
  if (!yaml_emitter_initialize(&emitter)) sp_oom_die();
  yaml_emitter_set_unicode(&emitter, 1);
  yaml_emitter_set_width(&emitter, (int)width);
  yaml_emitter_set_indent(&emitter, (int)indent);
  yaml_emitter_set_canonical(&emitter, (int)canonical);
  outbuf out = { NULL, 0, 0 };
  yaml_emitter_set_output(&emitter, write_out, &out);

  const char *problem = NULL;
  sp_int n = sp_json_len_fn(events);
  for (sp_int i = 0; i + EVENT_FIELDS <= n; i += EVENT_FIELDS) {
    yaml_event_t event;
    if (!make_event(&event, events, i)) {
      problem = "invalid event";
      break;
    }
    if (!yaml_emitter_emit(&emitter, &event)) {
      problem = emitter.problem ? emitter.problem : "emitter error";
      break;
    }
  }
  if (!problem && !yaml_emitter_flush(&emitter)) problem = "could not flush the output";
  yaml_emitter_delete(&emitter);
  if (problem) {
    free(out.p);
    sp_raise_cls("RuntimeError", problem);
  }

  char *s = sp_str_alloc_raw(out.len + 1);
  if (out.len) memcpy(s, out.p, out.len);
  s[out.len] = '\0';
  sp_str_set_len(s, out.len);
  free(out.p);
  return s;
}
