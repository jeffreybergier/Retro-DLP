#include "self_test.h"

#include <stdint.h>
#include <stdio.h>

#include "cJSON.h"
#include "quickjs.h"
#include "self_test_data.h"

static int test_cjson(void) {
  cJSON *document;
  cJSON *value;

  document = cJSON_ParseWithLength(retro_dlp_self_test_json,
                                   retro_dlp_self_test_json_length);
  if (document == NULL) {
    fprintf(stderr, "FAIL: cJSON could not parse JSON\n");
    return 1;
  }

  value = cJSON_GetObjectItemCaseSensitive(document, "enabled");
  if (!cJSON_IsTrue(value)) {
    fprintf(stderr, "FAIL: cJSON returned an unexpected value\n");
    cJSON_Delete(document);
    return 1;
  }

  cJSON_Delete(document);
  printf("PASS: cJSON\n");
  return 0;
}

static int test_quickjs(void) {
  JSRuntime *runtime;
  JSContext *context;
  JSValue result;
  int32_t number;
  int failed;

  runtime = JS_NewRuntime();
  if (runtime == NULL) {
    fprintf(stderr, "FAIL: QuickJS could not create a runtime\n");
    return 1;
  }

  context = JS_NewContext(runtime);
  if (context == NULL) {
    fprintf(stderr, "FAIL: QuickJS could not create a context\n");
    JS_FreeRuntime(runtime);
    return 1;
  }

  result = JS_Eval(context, retro_dlp_self_test_javascript,
                   retro_dlp_self_test_javascript_length, "<self-test>",
                   JS_EVAL_TYPE_GLOBAL);
  failed = JS_IsException(result) ||
           JS_ToInt32(context, &number, result) != 0 || number != 42;
  JS_FreeValue(context, result);
  JS_FreeContext(context);
  JS_FreeRuntime(runtime);

  if (failed) {
    fprintf(stderr, "FAIL: QuickJS evaluation returned an unexpected value\n");
    return 1;
  }

  printf("PASS: QuickJS\n");
  return 0;
}

int retro_dlp_run_self_tests(void) {
  int failures;

  failures = test_cjson();
  failures += test_quickjs();
  if (failures != 0)
    return 1;

  printf("PASS: retro-dlp self-test\n");
  return 0;
}
