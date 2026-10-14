/* sp_yaml.c -- the bridge between libyaml's parser and yaml.rb.

   libyaml reads the text and reports it as events (a mapping starts, a
   scalar, an alias, ...). This file hands those events to Ruby unchanged, as
   one flat Array with EVENT_FIELDS slots per event, and decides nothing:
   typing scalars, building Hashes and Arrays, aliases, merge keys and the
   safe_load rules are all in yaml.rb. Keeping the C to a translation keeps
   every hash key possible (the package ABI only builds String-keyed hashes)
   and the behaviour readable in one place.

   Slots per event: type, value, anchor, tag, quoted, style, line, column.
   type is libyaml's yaml_event_type_t, or EVENT_ERROR for a parse error, in
   which case value is the problem, anchor the context, quoted the problem
   offset and line/column the context mark -- the fields Psych's SyntaxError
   is built from. Strings carry their byte length, so a scalar holding "\0"
   survives. */
#include "spinel/runtime.h"
#include "yaml.h"
#include <string.h>

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
