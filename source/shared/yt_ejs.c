#include "yt_ejs.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "cJSON.h"
#include "quickjs.h"
#include "yt_ejs_bundle.h"
#include "yt_ejs_internal.h"

#define YT_EJS_DEFAULT_MEMORY_LIMIT (128U * 1024U * 1024U)
#define YT_EJS_DEFAULT_STACK_LIMIT (1024U * 1024U)
#define YT_EJS_DEFAULT_TIMEOUT_MS 30000UL

typedef struct {
  clock_t started;
  unsigned long timeout_milliseconds;
  int interrupted;
} YTEJSDeadline;

static char *copy_string(const char *source) {
  size_t length;
  char *copy;

  if (source == NULL)
    return NULL;
  length = strlen(source);
  copy = (char *)malloc(length + 1);
  if (copy != NULL)
    memcpy(copy, source, length + 1);
  return copy;
}

static void set_error_message(YTEJSResult *result, const char *message) {
  if (result == NULL || result->error_message != NULL || message == NULL)
    return;
  result->error_message = copy_string(message);
}

static int deadline_interrupt(JSRuntime *runtime, void *opaque) {
  YTEJSDeadline *deadline;
  clock_t now;
  double elapsed_milliseconds;

  (void)runtime;
  deadline = (YTEJSDeadline *)opaque;
  now = clock();
  if (now == (clock_t)-1 || deadline->started == (clock_t)-1)
    return 0;
  elapsed_milliseconds =
      ((double)(now - deadline->started) * 1000.0) / (double)CLOCKS_PER_SEC;
  if (elapsed_milliseconds < (double)deadline->timeout_milliseconds)
    return 0;
  deadline->interrupted = 1;
  return 1;
}

static int request_is_valid(const YTEJSRequest *request) {
  size_t index;

  if (request == NULL || request->challenge_count == 0 ||
      request->challenges == NULL ||
      (request->type != YT_EJS_CHALLENGE_SIGNATURE &&
       request->type != YT_EJS_CHALLENGE_N))
    return 0;
  for (index = 0; index < request->challenge_count; ++index) {
    if (request->challenges[index] == NULL)
      return 0;
  }
  return 1;
}

static const char *challenge_type_name(YTEJSChallengeType type) {
  return type == YT_EJS_CHALLENGE_N ? "n" : "sig";
}

static char *build_request_json(YTEJSSourceType source_type,
                                const char *player_source,
                                const YTEJSRequest *requests,
                                size_t request_count) {
  cJSON *document;
  cJSON *request_array;
  size_t request_index;
  char *json;

  document = cJSON_CreateObject();
  if (document == NULL)
    return NULL;
  if (!cJSON_AddStringToObject(
          document, "type",
          source_type == YT_EJS_SOURCE_PREPROCESSED ? "preprocessed"
                                                    : "player") ||
      !cJSON_AddStringToObject(
          document,
          source_type == YT_EJS_SOURCE_PREPROCESSED ? "preprocessed_player"
                                                    : "player",
          player_source)) {
    cJSON_Delete(document);
    return NULL;
  }
  if (source_type == YT_EJS_SOURCE_PLAYER &&
      !cJSON_AddTrueToObject(document, "output_preprocessed")) {
    cJSON_Delete(document);
    return NULL;
  }

  request_array = cJSON_AddArrayToObject(document, "requests");
  if (request_array == NULL) {
    cJSON_Delete(document);
    return NULL;
  }
  for (request_index = 0; request_index < request_count; ++request_index) {
    cJSON *request_object;
    cJSON *challenges;
    size_t challenge_index;

    request_object = cJSON_CreateObject();
    if (request_object == NULL ||
        !cJSON_AddItemToArray(request_array, request_object)) {
      cJSON_Delete(request_object);
      cJSON_Delete(document);
      return NULL;
    }
    if (!cJSON_AddStringToObject(request_object, "type",
                                 challenge_type_name(requests[request_index].type))) {
      cJSON_Delete(document);
      return NULL;
    }
    challenges = cJSON_AddArrayToObject(request_object, "challenges");
    if (challenges == NULL) {
      cJSON_Delete(document);
      return NULL;
    }
    for (challenge_index = 0;
         challenge_index < requests[request_index].challenge_count;
         ++challenge_index) {
      cJSON *challenge;

      challenge = cJSON_CreateString(
          requests[request_index].challenges[challenge_index]);
      if (challenge == NULL || !cJSON_AddItemToArray(challenges, challenge)) {
        cJSON_Delete(challenge);
        cJSON_Delete(document);
        return NULL;
      }
    }
  }

  json = cJSON_PrintUnformatted(document);
  cJSON_Delete(document);
  return json;
}

void yt_ejs_result_free(YTEJSResult *result) {
  size_t response_index;

  if (result == NULL)
    return;
  for (response_index = 0; response_index < result->response_count;
       ++response_index) {
    YTEJSResponse *response;
    size_t solution_index;

    response = &result->responses[response_index];
    for (solution_index = 0; solution_index < response->solution_count;
         ++solution_index)
      free(response->solutions[solution_index]);
    free(response->solutions);
    free(response->error);
  }
  free(result->responses);
  free(result->preprocessed_player);
  free(result->error_message);
  memset(result, 0, sizeof(*result));
}

static YTEJSStatus parse_response(const cJSON *response_json,
                                  const YTEJSRequest *request,
                                  YTEJSResponse *response) {
  const cJSON *type;
  const cJSON *data;
  size_t challenge_index;

  type = cJSON_GetObjectItemCaseSensitive(response_json, "type");
  if (!cJSON_IsString(type) || type->valuestring == NULL)
    return YT_EJS_ERR_INVALID_RESULT;
  if (strcmp(type->valuestring, "error") == 0) {
    const cJSON *error;

    error = cJSON_GetObjectItemCaseSensitive(response_json, "error");
    if (!cJSON_IsString(error) || error->valuestring == NULL)
      return YT_EJS_ERR_INVALID_RESULT;
    response->error = copy_string(error->valuestring);
    return response->error == NULL ? YT_EJS_ERR_OUT_OF_MEMORY : YT_EJS_OK;
  }
  if (strcmp(type->valuestring, "result") != 0)
    return YT_EJS_ERR_INVALID_RESULT;

  data = cJSON_GetObjectItemCaseSensitive(response_json, "data");
  if (!cJSON_IsObject(data))
    return YT_EJS_ERR_INVALID_RESULT;
  response->solutions =
      (char **)calloc(request->challenge_count, sizeof(*response->solutions));
  if (response->solutions == NULL)
    return YT_EJS_ERR_OUT_OF_MEMORY;
  response->solution_count = request->challenge_count;
  for (challenge_index = 0; challenge_index < request->challenge_count;
       ++challenge_index) {
    const cJSON *solution;

    solution = cJSON_GetObjectItemCaseSensitive(
        data, request->challenges[challenge_index]);
    if (!cJSON_IsString(solution) || solution->valuestring == NULL)
      return YT_EJS_ERR_INVALID_RESULT;
    response->solutions[challenge_index] = copy_string(solution->valuestring);
    if (response->solutions[challenge_index] == NULL)
      return YT_EJS_ERR_OUT_OF_MEMORY;
  }
  return YT_EJS_OK;
}

YTEJSStatus yt_ejs_parse_result_json(const char *json,
                                     const YTEJSRequest *requests,
                                     size_t request_count,
                                     YTEJSResult *result) {
  cJSON *document;
  const cJSON *type;
  const cJSON *responses;
  const cJSON *preprocessed;
  size_t response_index;
  YTEJSStatus status;

  if (json == NULL || requests == NULL || request_count == 0 || result == NULL)
    return YT_EJS_ERR_INVALID_ARGUMENT;
  memset(result, 0, sizeof(*result));
  document = cJSON_Parse(json);
  if (document == NULL)
    return YT_EJS_ERR_INVALID_RESULT;
  type = cJSON_GetObjectItemCaseSensitive(document, "type");
  responses = cJSON_GetObjectItemCaseSensitive(document, "responses");
  if (!cJSON_IsString(type) || type->valuestring == NULL ||
      strcmp(type->valuestring, "result") != 0 || !cJSON_IsArray(responses) ||
      (size_t)cJSON_GetArraySize(responses) != request_count) {
    cJSON_Delete(document);
    return YT_EJS_ERR_INVALID_RESULT;
  }

  result->responses =
      (YTEJSResponse *)calloc(request_count, sizeof(*result->responses));
  if (result->responses == NULL) {
    cJSON_Delete(document);
    return YT_EJS_ERR_OUT_OF_MEMORY;
  }
  result->response_count = request_count;
  for (response_index = 0; response_index < request_count; ++response_index) {
    status = parse_response(cJSON_GetArrayItem(responses, (int)response_index),
                            &requests[response_index],
                            &result->responses[response_index]);
    if (status != YT_EJS_OK) {
      cJSON_Delete(document);
      yt_ejs_result_free(result);
      return status;
    }
  }

  preprocessed =
      cJSON_GetObjectItemCaseSensitive(document, "preprocessed_player");
  if (preprocessed != NULL) {
    if (!cJSON_IsString(preprocessed) || preprocessed->valuestring == NULL) {
      cJSON_Delete(document);
      yt_ejs_result_free(result);
      return YT_EJS_ERR_INVALID_RESULT;
    }
    result->preprocessed_player = copy_string(preprocessed->valuestring);
    if (result->preprocessed_player == NULL) {
      cJSON_Delete(document);
      yt_ejs_result_free(result);
      return YT_EJS_ERR_OUT_OF_MEMORY;
    }
  }

  cJSON_Delete(document);
  return YT_EJS_OK;
}

static YTEJSStatus javascript_exception_status(JSContext *context,
                                               YTEJSDeadline *deadline,
                                               YTEJSResult *result) {
  JSValue exception;
  const char *message;
  YTEJSStatus status;

  if (deadline->interrupted) {
    set_error_message(result, "EJS execution deadline exceeded");
    return YT_EJS_ERR_TIMEOUT;
  }
  status = YT_EJS_ERR_JAVASCRIPT;
  exception = JS_GetException(context);
  message = JS_ToCString(context, exception);
  if (message != NULL) {
    set_error_message(result, message);
    if (strstr(message, "out of memory") != NULL)
      status = YT_EJS_ERR_OUT_OF_MEMORY;
    JS_FreeCString(context, message);
  } else {
    set_error_message(result, "unprintable JavaScript exception");
  }
  JS_FreeValue(context, exception);
  return status;
}

static YTEJSStatus evaluate(JSContext *context, const char *source,
                            size_t source_length, const char *filename,
                            YTEJSDeadline *deadline, YTEJSResult *result,
                            JSValue *value) {
  *value = JS_Eval(context, source, source_length, filename,
                   JS_EVAL_TYPE_GLOBAL);
  if (!JS_IsException(*value))
    return YT_EJS_OK;
  JS_FreeValue(context, *value);
  *value = JS_UNDEFINED;
  return javascript_exception_status(context, deadline, result);
}

YTEJSConfig yt_ejs_default_config(void) {
  YTEJSConfig config;

  config.memory_limit_bytes = YT_EJS_DEFAULT_MEMORY_LIMIT;
  config.stack_limit_bytes = YT_EJS_DEFAULT_STACK_LIMIT;
  config.timeout_milliseconds = YT_EJS_DEFAULT_TIMEOUT_MS;
  return config;
}

YTEJSStatus yt_ejs_solve(YTEJSSourceType source_type,
                         const char *player_source,
                         const YTEJSRequest *requests,
                         size_t request_count,
                         const YTEJSConfig *config,
                         YTEJSResult *result) {
  static const char isolation_check[] =
      "typeof std==='undefined'&&typeof os==='undefined'&&"
      "typeof require==='undefined'&&typeof fetch==='undefined'&&"
      "typeof XMLHttpRequest==='undefined'&&typeof WebSocket==='undefined'";
  static const char install_lib[] = "Object.assign(globalThis,lib);";
  static const char solve_script[] =
      "JSON.stringify(jsc(JSON.parse(globalThis.__retro_dlp_ejs_input)))";
  YTEJSConfig effective_config;
  YTEJSDeadline deadline;
  JSRuntime *runtime;
  JSContext *context;
  JSValue value;
  JSValue global;
  char *request_json;
  const char *result_json;
  YTEJSStatus status;
  size_t request_index;

  if (result == NULL)
    return YT_EJS_ERR_INVALID_ARGUMENT;
  memset(result, 0, sizeof(*result));
  if (player_source == NULL || requests == NULL || request_count == 0 ||
      (source_type != YT_EJS_SOURCE_PLAYER &&
       source_type != YT_EJS_SOURCE_PREPROCESSED))
    return YT_EJS_ERR_INVALID_ARGUMENT;
  for (request_index = 0; request_index < request_count; ++request_index) {
    if (!request_is_valid(&requests[request_index]))
      return YT_EJS_ERR_INVALID_ARGUMENT;
  }

  effective_config = config == NULL ? yt_ejs_default_config() : *config;
  if (effective_config.memory_limit_bytes == 0 ||
      effective_config.stack_limit_bytes == 0)
    return YT_EJS_ERR_INVALID_ARGUMENT;
  request_json =
      build_request_json(source_type, player_source, requests, request_count);
  if (request_json == NULL)
    return YT_EJS_ERR_OUT_OF_MEMORY;

  runtime = JS_NewRuntime();
  if (runtime == NULL) {
    free(request_json);
    return YT_EJS_ERR_OUT_OF_MEMORY;
  }
  JS_SetMemoryLimit(runtime, effective_config.memory_limit_bytes);
  JS_SetMaxStackSize(runtime, effective_config.stack_limit_bytes);
  JS_SetCanBlock(runtime, 0);
  deadline.started = clock();
  deadline.timeout_milliseconds = effective_config.timeout_milliseconds;
  deadline.interrupted = 0;
  JS_SetInterruptHandler(runtime, deadline_interrupt, &deadline);

  context = JS_NewContext(runtime);
  if (context == NULL) {
    JS_FreeRuntime(runtime);
    free(request_json);
    return YT_EJS_ERR_OUT_OF_MEMORY;
  }

  status = evaluate(context, isolation_check, sizeof(isolation_check) - 1,
                    "<isolation-check>", &deadline, result, &value);
  if (status != YT_EJS_OK)
    goto cleanup;
  if (JS_ToBool(context, value) != 1) {
    JS_FreeValue(context, value);
    set_error_message(result, "QuickJS context exposes a forbidden native API");
    status = YT_EJS_ERR_JAVASCRIPT;
    goto cleanup;
  }
  JS_FreeValue(context, value);

  status = evaluate(context, retro_dlp_ejs_lib, retro_dlp_ejs_lib_length,
                    "<yt-dlp-ejs-lib-0.8.0>", &deadline, result, &value);
  if (status != YT_EJS_OK)
    goto cleanup;
  JS_FreeValue(context, value);
  status = evaluate(context, install_lib, sizeof(install_lib) - 1,
                    "<yt-dlp-ejs-install>", &deadline, result, &value);
  if (status != YT_EJS_OK)
    goto cleanup;
  JS_FreeValue(context, value);
  status = evaluate(context, retro_dlp_ejs_core, retro_dlp_ejs_core_length,
                    "<yt-dlp-ejs-core-0.8.0>", &deadline, result, &value);
  if (status != YT_EJS_OK)
    goto cleanup;
  JS_FreeValue(context, value);

  global = JS_GetGlobalObject(context);
  if (JS_SetPropertyStr(context, global, "__retro_dlp_ejs_input",
                        JS_NewString(context, request_json)) < 0) {
    JS_FreeValue(context, global);
    status = javascript_exception_status(context, &deadline, result);
    goto cleanup;
  }
  JS_FreeValue(context, global);
  status = evaluate(context, solve_script, sizeof(solve_script) - 1,
                    "<retro-dlp-ejs-solve>", &deadline, result, &value);
  if (status != YT_EJS_OK)
    goto cleanup;
  result_json = JS_ToCString(context, value);
  if (result_json == NULL) {
    JS_FreeValue(context, value);
    status = javascript_exception_status(context, &deadline, result);
    goto cleanup;
  }
  status =
      yt_ejs_parse_result_json(result_json, requests, request_count, result);
  JS_FreeCString(context, result_json);
  JS_FreeValue(context, value);

cleanup:
  JS_FreeContext(context);
  JS_FreeRuntime(runtime);
  free(request_json);
  return status;
}

const char *yt_ejs_status_string(YTEJSStatus status) {
  switch (status) {
    case YT_EJS_OK:
      return "ok";
    case YT_EJS_ERR_INVALID_ARGUMENT:
      return "invalid_argument";
    case YT_EJS_ERR_OUT_OF_MEMORY:
      return "out_of_memory";
    case YT_EJS_ERR_JAVASCRIPT:
      return "javascript_error";
    case YT_EJS_ERR_TIMEOUT:
      return "timeout";
    case YT_EJS_ERR_INVALID_RESULT:
      return "invalid_result";
  }
  return "unknown";
}
