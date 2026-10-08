// KanonIME Node-API bridge (embedded Mozc, no IPC).
// Mozc pinned at b9c3fcbd6d76b19649ef572324fa9da2559bc18e.
// Logs op/status/lengths, never text content.
#include <node_api.h>

#include <cassert>
#include <chrono>
#include <memory>
#include <mutex>
#include <string>

#include "base/system_util.h"
#include "composer/key_parser.h"
#include "data_manager/oss/oss_data_manager.h"
#include "engine/engine.h"
#include "protocol/commands.pb.h"
#include "session/session_handler.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#include <hilog/log.h>

namespace {

constexpr unsigned int kLogDomain = 0xFF00;

std::unique_ptr<mozc::SessionHandler> g_handler;
uint64_t g_session_id = 0;
std::mutex g_session_mutex;

std::string EscapeJson(const std::string& s) {
  std::string out;
  out.reserve(s.size());
  for (char c : s) {
    switch (c) {
      case '\\': out += "\\\\"; break;
      case '"': out += "\\\""; break;
      case '\n': out += "\\n"; break;
      default:
        if (static_cast<unsigned char>(c) < 0x20) {
          constexpr char hex[] = "0123456789abcdef";
          out += "\\u00";
          out += hex[(static_cast<unsigned char>(c) >> 4) & 0xf];
          out += hex[static_cast<unsigned char>(c) & 0xf];
        } else {
          out += c;
        }
    }
  }
  return out;
}

bool Call(mozc::commands::Input& input, mozc::commands::Output* output) {
  input.set_id(g_session_id);
  input.mutable_config()->set_use_cascading_window(false);
  mozc::commands::Command command;
  *command.mutable_input() = input;
  if (!g_handler->EvalCommand(&command)) return false;
  if (output != nullptr) *output = command.output();
  return true;
}

bool ConfigureKeyboardRequest() {
  mozc::commands::Input input;
  input.set_type(mozc::commands::Input::SET_REQUEST);
  // Mix conversion and prediction for a touch keyboard. Desktop suggestions
  // restrict realtime conversion to one result, even for an ambiguous kana.
  auto* request = input.mutable_request();
  request->set_mixed_conversion(true);
  request->set_candidate_page_size(20);
  request->set_is_a11y_talkback_enabled(true);
  request->set_crossing_edge_behavior(mozc::commands::Request::DO_NOTHING);
  return Call(input, nullptr);
}

bool EnsureSession() {
  if (g_handler && g_session_id != 0) {
    // Session watchdog is disabled for the embedded engine. Do not run a global
    // cleanup command on every keystroke.
    return true;
  }
  auto engine =
      mozc::Engine::CreateEngine(std::make_unique<mozc::oss::OssDataManager>());
  if (!engine.ok()) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, kLogDomain, "KanonBridge",
                 "CreateEngine failed");
    return false;
  }
  g_handler = std::make_unique<mozc::SessionHandler>(std::move(*engine));
  mozc::commands::Input input;
  input.set_type(mozc::commands::Input::CREATE_SESSION);
  input.mutable_capability()->set_text_deletion(
      mozc::commands::Capability::DELETE_PRECEDING_TEXT);
  mozc::commands::Command command;
  *command.mutable_input() = input;
  g_handler->EvalCommand(&command);
  if (command.output().error_code() != mozc::commands::Output::SESSION_SUCCESS) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, kLogDomain, "KanonBridge",
                 "CreateSession failed");
    g_handler.reset();
    return false;
  }
  g_session_id = command.output().id();
  if (!ConfigureKeyboardRequest()) {
    g_session_id = 0;
    g_handler.reset();
    return false;
  }
  // Kanon feeds both kana flicks and QWERTY through a hiragana composition.
  mozc::commands::Input mode;
  mode.set_type(mozc::commands::Input::SEND_COMMAND);
  mode.mutable_command()->set_type(
      mozc::commands::SessionCommand::SWITCH_COMPOSITION_MODE);
  mode.mutable_command()->set_composition_mode(mozc::commands::HIRAGANA);
  Call(mode, nullptr);
  return true;
}

std::string OutputToJson(bool ok, const mozc::commands::Output& output) {
  std::string json = std::string("{\"ok\":") + (ok ? "true" : "false");
  std::string preedit;
  std::string focused_reading;
  for (const auto& seg : output.preedit().segment()) {
    preedit += seg.value();
    if (seg.annotation() == mozc::commands::Preedit::Segment::HIGHLIGHT) {
      focused_reading = seg.has_key() ? seg.key() : seg.value();
    }
  }
  json += ",\"focused_reading\":\"" + EscapeJson(focused_reading) + "\"";
  json += ",\"preedit_len\":" + std::to_string(preedit.size());
  json += ",\"preedit\":\"" + EscapeJson(preedit) + "\"";
  // Mozc reports a Unicode-character offset; ArkTS strings use UTF-16 units.
  size_t caret_utf16 = 0;
  size_t characters = 0;
  for (unsigned char byte : preedit) {
    if ((byte & 0xc0) == 0x80) continue;
    if (characters >= output.preedit().cursor()) break;
    caret_utf16 += byte >= 0xf0 ? 2 : 1;
    ++characters;
  }
  json += ",\"caret_utf16\":" + std::to_string(caret_utf16);
  json += ",\"segcount\":" +
          std::to_string(output.preedit().segment_size());
  const auto& all_candidates = output.all_candidate_words();
  if (all_candidates.has_focused_index() &&
      all_candidates.focused_index() < all_candidates.candidates_size()) {
    json += ",\"focused_id\":" + std::to_string(
        all_candidates.candidates(all_candidates.focused_index()).id());
  }
  json += ",\"ncand\":" +
          std::to_string(output.candidate_window().candidate_size());
  json += ",\"candidates\":[";
  bool first = true;
  std::string candlens = ",\"candlens\":[";
  bool firstlen = true;
  for (const auto& cand : output.candidate_window().candidate()) {
    if (!first) json += ",";
    first = false;
    json += "{\"id\":" + std::to_string(cand.id()) + ",\"value\":\"" +
            EscapeJson(cand.value()) + "\"}";
    // REQ-07: 値ではなく長さ（バイト）のみを診断用に付ける。
    if (!firstlen) candlens += ",";
    firstlen = false;
    candlens += std::to_string(cand.value().size());
  }
  json += "]";
  json += candlens + "]";
  if (output.has_result()) {
    json += ",\"result\":\"" + EscapeJson(output.result().value()) + "\"";
  }
  json += "}";
  return json;
}

std::string GetStringArg(napi_env env, napi_callback_info info, int index) {
  size_t argc = 2;
  napi_value argv[2];
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if ((int)argc <= index) return "";
  size_t len = 0;
  napi_get_value_string_utf8(env, argv[index], nullptr, 0, &len);
  std::string s(len, '\0');
  napi_get_value_string_utf8(env, argv[index], s.data(), len + 1, nullptr);
  return s;
}

napi_value ReturnString(napi_env env, const std::string& s) {
  napi_value v;
  napi_create_string_utf8(env, s.c_str(), s.size(), &v);
  return v;
}

napi_value BridgeInit(napi_env env, napi_callback_info info) {
  std::lock_guard<std::mutex> lock(g_session_mutex);
  std::string profile = GetStringArg(env, info, 0);
  if (!profile.empty()) {
    mozc::SystemUtil::SetUserProfileDirectory(profile);
  }
  bool ok = EnsureSession();
  OH_LOG_Print(LOG_APP, LOG_INFO, kLogDomain, "KanonBridge", "init ok=%d",
               (int)ok);
  napi_value v;
  napi_get_boolean(env, ok, &v);
  return v;
}

napi_value BridgeConvert(napi_env env, napi_callback_info info) {
  std::lock_guard<std::mutex> lock(g_session_mutex);
  std::string keys = GetStringArg(env, info, 0);
  mozc::commands::Output output;
  bool ok = false;
  if (EnsureSession()) {
    ok = true;
    for (size_t i = 0; i < keys.size() && ok; ++i) {
      mozc::commands::Input input;
      input.set_type(mozc::commands::Input::SEND_KEY);
      input.mutable_key()->set_key_code(keys[i]);
      input.set_request_suggestion(i + 1 == keys.size());
      ok = Call(input, &output);
    }
  }
  OH_LOG_Print(LOG_APP, LOG_INFO, kLogDomain, "KanonBridge",
               "convert ok=%d nkeys=%d ncand=%d", (int)ok, (int)keys.size(),
               ok ? output.candidate_window().candidate_size() : -1);
  return ReturnString(env, OutputToJson(ok, output));
}

napi_value BridgeSelect(napi_env env, napi_callback_info info) {
  std::lock_guard<std::mutex> lock(g_session_mutex);
  size_t argc = 1;
  napi_value argv[1];
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  int32_t id = 0;
  napi_get_value_int32(env, argv[0], &id);
  mozc::commands::Output output;
  mozc::commands::Input input;
  input.set_type(mozc::commands::Input::SEND_COMMAND);
  input.mutable_command()->set_type(
      mozc::commands::SessionCommand::SELECT_CANDIDATE);
  input.mutable_command()->set_id((uint32_t)id);
  bool ok = Call(input, &output);
  OH_LOG_Print(LOG_APP, LOG_INFO, kLogDomain, "KanonBridge", "select ok=%d",
               (int)ok);
  return ReturnString(env, OutputToJson(ok, output));
}

napi_value BridgeSubmit(napi_env env, napi_callback_info info) {
  std::lock_guard<std::mutex> lock(g_session_mutex);
  mozc::commands::KeyEvent key;
  bool ok = false;
  mozc::commands::Output output;
  if (mozc::KeyParser::ParseKey("Enter", &key)) {
    mozc::commands::Input input;
    input.set_type(mozc::commands::Input::SEND_KEY);
    *input.mutable_key() = key;
    ok = Call(input, &output);
  }
  OH_LOG_Print(LOG_APP, LOG_INFO, kLogDomain, "KanonBridge", "submit ok=%d",
               (int)ok);
  return ReturnString(env, OutputToJson(ok, output));
}

napi_value BridgeSpace(napi_env env, napi_callback_info info) {
  std::lock_guard<std::mutex> lock(g_session_mutex);
  (void)info;
  // 変換開始はSpaceキー＋request.is_a11y_talkback_enabled=trueで送る。
  // 素のSPACEキーではcandidate_list_visible_=falseのままcandidate_windowが
  // 埋まらない（session.cc IsPureSpaceKey / engine_converter.cc:178）。
  // 当方の候補バーは常時表示のため可視扱いが正当。副作用は候補への音声説明
  // 付与のみでJSON出力には使わない。
  mozc::commands::KeyEvent key;
  bool ok = false;
  mozc::commands::Output output;
  if (mozc::KeyParser::ParseKey("Space", &key)) {
    // 可視フラグはセッション単位のrequest_で保持されるため、先にSET_REQUESTを送る。
    // SET_REQUEST replaces the request; retain mixed prediction and page size.
    if (!ConfigureKeyboardRequest()) {
      return ReturnString(env, OutputToJson(false, output));
    }
    mozc::commands::Input input;
    input.set_type(mozc::commands::Input::SEND_KEY);
    *input.mutable_key() = key;
    ok = Call(input, &output);
  }
  OH_LOG_Print(LOG_APP, LOG_INFO, kLogDomain, "KanonBridge", "space ok=%d",
               (int)ok);
  return ReturnString(env, OutputToJson(ok, output));
}

// 先頭文節のみ確定し、残りは未確定のまま続ける（SUBMIT_CANDIDATE）。
// divergence注記：mobile向け部分確定。候補が無い状態では何も起きない。
napi_value BridgeSubmitCandidate(napi_env env, napi_callback_info info) {
  std::lock_guard<std::mutex> lock(g_session_mutex);
  size_t argc = 1;
  napi_value argv[1];
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  int32_t id = 0;
  napi_get_value_int32(env, argv[0], &id);
  mozc::commands::Output output;
  mozc::commands::Input input;
  input.set_type(mozc::commands::Input::SEND_COMMAND);
  input.mutable_command()->set_type(
      mozc::commands::SessionCommand::SUBMIT_CANDIDATE);
  input.mutable_command()->set_id((uint32_t)id);
  bool ok = Call(input, &output);
  OH_LOG_Print(LOG_APP, LOG_INFO, kLogDomain, "KanonBridge",
               "submitCandidate ok=%d",
               (int)ok);
  return ReturnString(env, OutputToJson(ok, output));
}

// セッション内Backspace（部分確定後の残り読みの削除用。reset＋再送しない）。
napi_value BridgeBackspace(napi_env env, napi_callback_info info) {
  std::lock_guard<std::mutex> lock(g_session_mutex);
  (void)info;
  mozc::commands::KeyEvent key;
  bool ok = false;
  mozc::commands::Output output;
  if (mozc::KeyParser::ParseKey("Backspace", &key)) {
    mozc::commands::Input input;
    input.set_type(mozc::commands::Input::SEND_KEY);
    *input.mutable_key() = key;
    ok = Call(input, &output);
  }
  OH_LOG_Print(LOG_APP, LOG_INFO, kLogDomain, "KanonBridge",
               "backspace ok=%d",
               (int)ok);
  return ReturnString(env, OutputToJson(ok, output));
}

napi_value BridgeReset(napi_env env, napi_callback_info info) {
  std::lock_guard<std::mutex> lock(g_session_mutex);
  (void)info;
  mozc::commands::Input input;
  input.set_type(mozc::commands::Input::SEND_COMMAND);
  input.mutable_command()->set_type(
      mozc::commands::SessionCommand::RESET_CONTEXT);
  bool ok = Call(input, nullptr);
  napi_value v;
  napi_get_boolean(env, ok, &v);
  return v;
}

// Normal typing uses this worker API. The synchronous exports remain for the
// diagnostic probe. Both paths share the same session lock.
struct AsyncOperation {
  napi_async_work work = nullptr;
  napi_deferred deferred = nullptr;
  std::string operation;
  std::string text;
  int32_t candidate_id = 0;
  std::string json = "{\"ok\":false}";
};

std::string ExecuteOperation(const AsyncOperation& task) {
  std::lock_guard<std::mutex> lock(g_session_mutex);
  if (task.operation == "init") {
    if (!task.text.empty()) {
      mozc::SystemUtil::SetUserProfileDirectory(task.text);
    }
    return EnsureSession() ? "{\"ok\":true}" : "{\"ok\":false}";
  }
  mozc::commands::Output output;
  bool ok = false;
  if (!g_handler || g_session_id == 0) return OutputToJson(false, output);
  if (task.operation == "convert") {
    ok = true;
    for (size_t i = 0; i < task.text.size() && ok; ++i) {
      mozc::commands::Input input;
      input.set_type(mozc::commands::Input::SEND_KEY);
      input.mutable_key()->set_key_code(task.text[i]);
      // A flick/replay can contain several roman characters. Only compute
      // candidates after the last character; intermediate output is not shown.
      input.set_request_suggestion(i + 1 == task.text.size());
      ok = Call(input, &output);
    }
  } else if (task.operation == "literal") {
    // Whole UTF-8 text, not one SEND_KEY per byte. AS_IS retains punctuation
    // and other literal characters in the composition instead of committing.
    mozc::commands::Input input;
    input.set_type(mozc::commands::Input::SEND_KEY);
    auto* key = input.mutable_key();
    key->set_special_key(mozc::commands::KeyEvent::TEXT_INPUT);
    key->set_key_string(task.text);
    key->set_input_style(mozc::commands::KeyEvent::AS_IS);
    input.set_request_suggestion(true);
    ok = Call(input, &output) && output.consumed();
  } else {
    mozc::commands::Input input;
    if (task.operation == "arrowLeft" || task.operation == "arrowRight") {
      // Software arrows move the composing cursor or resize a conversion
      // segment, according to Mozc's current state in the same session.
      input.set_type(mozc::commands::Input::SEND_KEY);
      input.mutable_key()->set_special_key(task.operation == "arrowLeft" ?
          mozc::commands::KeyEvent::VIRTUAL_LEFT :
          mozc::commands::KeyEvent::VIRTUAL_RIGHT);
    } else if (task.operation == "space" || task.operation == "submit" ||
        task.operation == "backspace") {
      if (task.operation == "space" && !ConfigureKeyboardRequest()) {
        return OutputToJson(false, output);
      }
      mozc::commands::KeyEvent key;
      const char* name = task.operation == "space" ? "Space" :
                         task.operation == "submit" ? "Enter" : "Backspace";
      if (!mozc::KeyParser::ParseKey(name, &key)) return OutputToJson(false, output);
      input.set_type(mozc::commands::Input::SEND_KEY);
      *input.mutable_key() = key;
    } else {
      input.set_type(mozc::commands::Input::SEND_COMMAND);
      if (task.operation == "selectCandidate" || task.operation == "submitCandidate" ||
          task.operation == "highlightCandidate") {
        const auto type = task.operation == "highlightCandidate" ?
            mozc::commands::SessionCommand::HIGHLIGHT_CANDIDATE :
            task.operation == "selectCandidate" ?
            mozc::commands::SessionCommand::SELECT_CANDIDATE :
            mozc::commands::SessionCommand::SUBMIT_CANDIDATE;
        input.mutable_command()->set_type(type);
        input.mutable_command()->set_id(static_cast<uint32_t>(task.candidate_id));
      } else if (task.operation == "reset") {
        input.mutable_command()->set_type(mozc::commands::SessionCommand::RESET_CONTEXT);
      } else {
        return OutputToJson(false, output);
      }
    }
    ok = Call(input, &output);
  }
  if (ok && (task.operation == "arrowLeft" || task.operation == "arrowRight")) {
    // Width adjustment intentionally hides Mozc's desktop candidate window.
    // Re-highlight its current candidate to show the resized segment's list
    // without cycling candidates, committing text or changing the boundary.
    const auto& candidates = output.all_candidate_words();
    if (candidates.has_focused_index() &&
        candidates.focused_index() < candidates.candidates_size()) {
      mozc::commands::Input show;
      show.set_type(mozc::commands::Input::SEND_COMMAND);
      show.mutable_command()->set_type(
          mozc::commands::SessionCommand::HIGHLIGHT_CANDIDATE);
      show.mutable_command()->set_id(
          candidates.candidates(candidates.focused_index()).id());
      ok = Call(show, &output);
    }
  }
  return OutputToJson(ok, output);
}

void ExecuteAsync(napi_env env, void* data) {
  auto* task = static_cast<AsyncOperation*>(data);
  const auto start = std::chrono::steady_clock::now();
  try {
    task->json = ExecuteOperation(*task);
  } catch (...) {
    task->json = "{\"ok\":false}";
  }
  const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::steady_clock::now() - start).count();
  if (elapsed >= 16) {
    OH_LOG_Print(LOG_APP, LOG_INFO, kLogDomain, "KanonBridge",
                 "worker op=%{public}s duration_ms=%{public}lld",
                 task->operation.c_str(), static_cast<long long>(elapsed));
  }
}

void CompleteAsync(napi_env env, napi_status status, void* data) {
  std::unique_ptr<AsyncOperation> task(static_cast<AsyncOperation*>(data));
  if (status == napi_ok) {
    napi_resolve_deferred(env, task->deferred, ReturnString(env, task->json));
  } else {
    napi_value message;
    napi_value error;
    napi_create_string_utf8(env, "Native operation cancelled", NAPI_AUTO_LENGTH, &message);
    napi_create_error(env, nullptr, message, &error);
    napi_reject_deferred(env, task->deferred, error);
  }
  napi_delete_async_work(env, task->work);
}

napi_value BridgeExecuteAsync(napi_env env, napi_callback_info info) {
  auto task = std::make_unique<AsyncOperation>();
  task->operation = GetStringArg(env, info, 0);
  task->text = GetStringArg(env, info, 1);
  const auto& operation = task->operation;
  if (operation != "init" && operation != "convert" && operation != "literal" && operation != "space" &&
      operation != "submit" && operation != "backspace" && operation != "reset" &&
      operation != "selectCandidate" && operation != "submitCandidate" &&
      operation != "highlightCandidate" && operation != "arrowLeft" &&
      operation != "arrowRight") {
    napi_throw_range_error(env, nullptr, "Unknown native operation");
    return nullptr;
  }
  size_t argc = 3;
  napi_value argv[3];
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (argc > 2) napi_get_value_int32(env, argv[2], &task->candidate_id);
  napi_value promise;
  napi_value name;
  if (napi_create_promise(env, &task->deferred, &promise) != napi_ok ||
      napi_create_string_utf8(env, "kanonEngine", NAPI_AUTO_LENGTH, &name) != napi_ok ||
      napi_create_async_work(env, nullptr, name, ExecuteAsync, CompleteAsync,
                             task.get(), &task->work) != napi_ok ||
      napi_queue_async_work(env, task->work) != napi_ok) {
    if (task->work != nullptr) napi_delete_async_work(env, task->work);
    napi_throw_error(env, nullptr, "Could not queue native operation");
    return nullptr;
  }
  task.release();
  return promise;
}

#define DECL_FN(name, fn) \
  { name, nullptr, fn, nullptr, nullptr, nullptr, napi_default, nullptr }

napi_value InitModule(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
      DECL_FN("init", BridgeInit),
      DECL_FN("convert", BridgeConvert),
      DECL_FN("selectCandidate", BridgeSelect),
      DECL_FN("submit", BridgeSubmit),
      DECL_FN("submitCandidate", BridgeSubmitCandidate),
      DECL_FN("backspace", BridgeBackspace),
      DECL_FN("space", BridgeSpace),
      DECL_FN("reset", BridgeReset),
      DECL_FN("executeAsync", BridgeExecuteAsync),
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
  return exports;
}

}  // namespace

static napi_module kBridgeModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = InitModule,
    .nm_modname = "kanon_bridge",
    .nm_priv = nullptr,
    .reserved = {nullptr},
};

extern "C" __attribute__((constructor)) void RegisterKanonBridge() {
  napi_module_register(&kBridgeModule);
}
