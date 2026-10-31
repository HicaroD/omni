/* macOS ships ICU. UText keeps match/capture offsets in original UTF-8 bytes. */
#include "platform.h"
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <unicode/uregex.h>
#include <unicode/ustring.h>
#include <unicode/uchar.h>
#include <unicode/utf8.h>

typedef struct { URegularExpression *regex; bool expand, word; } Matcher;
typedef struct { unsigned char *data; size_t length, capacity; } Bytes;

static bool append(Bytes *out, const void *data, size_t size) {
    if (size > SIZE_MAX - out->length) return false;
    size_t need = out->length + size;
    if (need > out->capacity) {
        size_t cap = need > SIZE_MAX / 2 ? need : need * 2 + 1;
        void *p = realloc(out->data, cap);
        if (!p) return false;
        out->data = p; out->capacity = cap;
    }
    if (size) memcpy(out->data + out->length, data, size);
    out->length = need;
    return true;
}

int32_t omni_match_open(void *query, uint64_t length, bool regex, bool sensitive, bool word, void **handle) {
    *handle = NULL;
    if (length > INT32_MAX / 2) return -1;
    UErrorCode status = U_ZERO_ERROR;
    UChar *pattern = malloc((length + 1) * sizeof(UChar));
    Matcher *m = calloc(1, sizeof(*m));
    if (!pattern || !m) { free(pattern); free(m); return -1; }
    int32_t count;
    u_strFromUTF8(pattern, (int32_t)length + 1, &count, query ? query : "", (int32_t)length, &status);
    uint32_t flags = (regex ? 0 : UREGEX_LITERAL) | (sensitive ? 0 : UREGEX_CASE_INSENSITIVE);
    if (U_SUCCESS(status)) m->regex = uregex_open(pattern, count, flags, NULL, &status);
    free(pattern);
    if (U_FAILURE(status) || !m->regex) { omni_match_close(m); return -1; }
    uregex_setTimeLimit(m->regex, 100, &status);
    uregex_setStackLimit(m->regex, 1024 * 1024, &status);
    if (U_FAILURE(status)) { omni_match_close(m); return -1; }
    m->expand = regex; m->word = word;
    *handle = m;
    return 0;
}

void omni_match_close(void *handle) {
    Matcher *m = handle;
    if (m) { if (m->regex) uregex_close(m->regex); free(m); }
}

static bool word_at(const unsigned char *text, int32_t length, int32_t at, bool previous) {
    UChar32 cp;
    if (previous) { if (!at) return false; U8_PREV(text, 0, at, cp); }
    else { if (at >= length) return false; U8_NEXT(text, at, length, cp); }
    if (cp < 0) return false;
    int8_t category = u_charType(cp);
    return cp == '_' || u_isalnum(cp) || category == U_LETTER_NUMBER ||
        category == U_OTHER_NUMBER || category == U_NON_SPACING_MARK ||
        category == U_COMBINING_SPACING_MARK || category == U_ENCLOSING_MARK;
}

static bool expand(Matcher *m, const unsigned char *text, const unsigned char *replacement, size_t length, Bytes *out, UErrorCode *status) {
    for (size_t i = 0; i < length;) {
        unsigned char c = replacement[i++];
        if (m->expand && c == '$') {
            if (i == length) return false;
            if (replacement[i] == '$') { i++; if (!append(out, "$", 1)) return false; continue; }
            int32_t group = 0;
            if (replacement[i] == '{') {
                size_t begin = ++i;
                while (i < length && replacement[i] != '}') i++;
                if (i == length || i == begin || i - begin > INT32_MAX) return false;
                group = uregex_groupNumberFromCName(m->regex, (const char *)replacement + begin, (int32_t)(i - begin), status);
                i++;
            } else {
                size_t begin = i;
                while (i < length && replacement[i] >= '0' && replacement[i] <= '9') {
                    if (group > INT32_MAX / 10 - 10) return false;
                    group = group * 10 + replacement[i++] - '0';
                }
                if (i == begin) return false;
            }
            int64_t start = uregex_start64(m->regex, group, status);
            int64_t end = uregex_end64(m->regex, group, status);
            if (U_FAILURE(*status)) return false;
            if (start >= 0 && !append(out, text + start, (size_t)(end - start))) return false;
        } else {
            /* Only these replacement escapes are interpreted; unknown escapes stay literal. */
            if (c == '\\' && i < length) {
                if (replacement[i] == 'n') { c = '\n'; i++; }
                else if (replacement[i] == 't') { c = '\t'; i++; }
                else if (replacement[i] == '\\') { c = '\\'; i++; }
            }
            if (!append(out, &c, 1)) return false;
        }
    }
    return true;
}

int32_t omni_match_next(void *handle, void *bytes, uint64_t length, uint64_t offset, void *replacement, uint64_t replacement_length, uint64_t *start, uint64_t *end, void **after, uint64_t *after_length) {
    Matcher *m = handle;
    if (!m || length > INT32_MAX || offset > length) return -1;
    const unsigned char *text = bytes ? bytes : (const void *)"";
    UErrorCode status = U_ZERO_ERROR;
    UText *ut = utext_openUTF8(NULL, (const char *)text, (int64_t)length, &status);
    uregex_setUText(m->regex, ut, &status);
    utext_close(ut);
    while (U_SUCCESS(status) && uregex_find64(m->regex, (int64_t)offset, &status)) {
        int64_t a = uregex_start64(m->regex, 0, &status), b = uregex_end64(m->regex, 0, &status);
        if (U_FAILURE(status)) return -1;
        if (m->word && (word_at(text, (int32_t)length, (int32_t)a, true) || word_at(text, (int32_t)length, (int32_t)b, false))) {
            if ((uint64_t)a >= length) break;
            int32_t next = (int32_t)a; U8_FWD_1(text, next, (int32_t)length); offset = (uint64_t)next;
            continue;
        }
        Bytes out = {0};
        if (!expand(m, text, replacement, replacement_length, &out, &status)) { free(out.data); return -2; }
        *start = (uint64_t)a; *end = (uint64_t)b;
        *after = out.data; *after_length = out.length;
        return 1;
    }
    return U_FAILURE(status) ? -1 : 0;
}
