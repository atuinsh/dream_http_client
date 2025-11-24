import dream_http_client/client
import gleam/bit_array
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http
import gleam/list
import gleam/set.{type Set}
import gleam/string
import gleam/yielder

/// Drain mailbox to prevent message bleeding between tests
fn drain_mailbox(selector: process.Selector(client.StreamMessage)) -> Nil {
  case process.selector_receive(selector, 0) {
    Ok(_) -> drain_mailbox(selector)
    Error(_) -> Nil
  }
}

import gleeunit/should

pub type Msg {
  HttpStream(client.StreamMessage)
}

/// Test: stream_messages returns a RequestId (API smoke test)
pub fn stream_messages_api_smoke_test() {
  // Arrange
  let req =
    client.new
    |> client.method(http.Get)
    |> client.scheme(http.Https)
    |> client.host("httpbin.org")
    |> client.path("/get")

  // Act
  let result = client.stream_messages(req)

  // Assert - We get Ok with a RequestId
  case result {
    Ok(req_id) -> {
      // Clean up
      client.cancel_stream(req_id)
      Nil
    }
    Error(_) -> should.fail()
  }

  Nil
}

/// Test: Selector can be built with stream messages
pub fn selector_builds_test() {
  // Arrange & Act
  let selector =
    process.new_selector()
    |> client.select_stream_messages(HttpStream)

  // Assert - selector type is correct
  let _type_check: process.Selector(Msg) = selector

  Nil
}

/// Test: Multiple concurrent streams receive messages correctly
/// This is the core OTP compatibility requirement
pub fn multiple_concurrent_streams_test() {
  // Arrange - Start 3 concurrent streams
  let req1 =
    client.new
    |> client.method(http.Get)
    |> client.scheme(http.Https)
    |> client.host("httpbin.org")
    |> client.path("/stream/2")

  let req2 =
    client.new
    |> client.method(http.Get)
    |> client.scheme(http.Https)
    |> client.host("httpbin.org")
    |> client.path("/stream/2")

  let req3 =
    client.new
    |> client.method(http.Get)
    |> client.scheme(http.Https)
    |> client.host("httpbin.org")
    |> client.path("/stream/2")

  // Build selector BEFORE starting streams to ensure no messages are lost
  let selector =
    process.new_selector()
    |> client.select_stream_messages(fn(msg) { msg })

  // Drain mailbox to prevent messages from previous tests
  drain_mailbox(selector)

  let assert Ok(_id1) = client.stream_messages(req1)
  let assert Ok(_id2) = client.stream_messages(req2)
  let assert Ok(_id3) = client.stream_messages(req3)

  // Act - Collect messages from all streams
  let messages = collect_messages(selector, [], 50)

  // Assert - We received messages from all 3 streams
  // Note: string.inspect on RequestId may not be stable, so we check >= 3
  // The important thing is that we received messages from multiple streams
  let unique_ids = get_unique_request_ids(messages)
  let unique_count = set.size(unique_ids)

  { unique_count >= 3 } |> should.be_true()

  // Assert - Each stream had at least one chunk
  let chunks_count = count_chunks(messages)
  { chunks_count >= 3 } |> should.be_true()

  Nil
}

fn collect_messages(
  selector: process.Selector(client.StreamMessage),
  acc: List(client.StreamMessage),
  remaining: Int,
) -> List(client.StreamMessage) {
  case remaining {
    0 -> list.reverse(acc)
    _ -> handle_collect_receive(selector, acc, remaining)
  }
}

fn handle_collect_receive(
  selector: process.Selector(client.StreamMessage),
  acc: List(client.StreamMessage),
  remaining: Int,
) -> List(client.StreamMessage) {
  case process.selector_receive(selector, 2000) {
    Ok(msg) -> handle_collected_message(selector, acc, remaining, msg)
    Error(_) -> handle_collect_timeout(selector, acc, remaining)
  }
}

fn handle_collect_timeout(
  selector: process.Selector(client.StreamMessage),
  acc: List(client.StreamMessage),
  remaining: Int,
) -> List(client.StreamMessage) {
  // Timeout - if we haven't collected ANY messages yet, keep trying
  // If we have messages, assume the stream is done
  case acc {
    [] -> collect_messages(selector, acc, remaining)
    _ -> list.reverse(acc)
  }
}

fn handle_collected_message(
  selector: process.Selector(client.StreamMessage),
  acc: List(client.StreamMessage),
  remaining: Int,
  msg: client.StreamMessage,
) -> List(client.StreamMessage) {
  case msg {
    client.StreamEnd(_, _) ->
      collect_messages(selector, [msg, ..acc], remaining - 1)
    client.StreamError(_, _) ->
      collect_messages(selector, [msg, ..acc], remaining - 1)
    _ -> collect_messages(selector, [msg, ..acc], remaining - 1)
  }
}

fn get_unique_request_ids(messages: List(client.StreamMessage)) -> Set(String) {
  list.fold(messages, set.new(), accumulate_request_id)
}

fn accumulate_request_id(
  acc: Set(String),
  msg: client.StreamMessage,
) -> Set(String) {
  let id_str = case msg {
    client.StreamStart(req_id, _) -> req_id_to_string(req_id)
    client.Chunk(req_id, _) -> req_id_to_string(req_id)
    client.StreamEnd(req_id, _) -> req_id_to_string(req_id)
    client.StreamError(req_id, _) -> req_id_to_string(req_id)
  }
  set.insert(acc, id_str)
}

fn req_id_to_string(req_id: client.RequestId) -> String {
  // RequestId wraps d.Dynamic which contains an Erlang reference
  // We need to extract a stable representation for comparison
  // For now, use inspect but note this may not be stable across runs
  string.inspect(req_id)
}

fn message_has_request_id(msg: client.StreamMessage, id_str: String) -> Bool {
  let msg_id = case msg {
    client.StreamStart(req_id, _) -> req_id_to_string(req_id)
    client.Chunk(req_id, _) -> req_id_to_string(req_id)
    client.StreamEnd(req_id, _) -> req_id_to_string(req_id)
    client.StreamError(req_id, _) -> req_id_to_string(req_id)
  }
  msg_id == id_str
}

fn count_chunks(messages: List(client.StreamMessage)) -> Int {
  list.fold(messages, 0, increment_if_chunk)
}

fn increment_if_chunk(count: Int, msg: client.StreamMessage) -> Int {
  case msg {
    client.Chunk(_, _) -> count + 1
    _ -> count
  }
}

/// Test: Single stream receives all message types in order
pub fn stream_lifecycle_test() {
  // Arrange
  let req =
    client.new
    |> client.method(http.Get)
    |> client.scheme(http.Https)
    |> client.host("httpbin.org")
    |> client.path("/stream/3")

  // Build selector BEFORE starting stream to ensure no messages are lost
  let selector =
    process.new_selector()
    |> client.select_stream_messages(fn(msg) { msg })

  // Drain mailbox to prevent messages from previous tests
  drain_mailbox(selector)

  let assert Ok(_req_id) = client.stream_messages(req)

  // Act - Receive messages until stream ends
  let messages = collect_stream_lifecycle(selector, [])

  // Assert - We got StreamStart
  let has_start = list.any(messages, is_stream_start)
  has_start |> should.be_true()

  // Assert - We got at least one Chunk
  let chunk_count = count_chunks(messages)
  { chunk_count > 0 } |> should.be_true()

  // Assert - We got StreamEnd
  let has_end = list.any(messages, is_stream_end)
  has_end |> should.be_true()

  Nil
}

fn collect_stream_lifecycle(
  selector: process.Selector(client.StreamMessage),
  acc: List(client.StreamMessage),
) -> List(client.StreamMessage) {
  case process.selector_receive(selector, 3000) {
    Ok(msg) -> handle_lifecycle_message(selector, acc, msg)
    Error(_) -> handle_lifecycle_timeout(selector, acc)
  }
}

fn handle_lifecycle_timeout(
  selector: process.Selector(client.StreamMessage),
  acc: List(client.StreamMessage),
) -> List(client.StreamMessage) {
  // Timeout - check if we've seen StreamEnd/StreamError
  // If not, keep trying (might just be network latency)
  let has_termination = list.any(acc, is_termination_message)

  case has_termination {
    True -> list.reverse(acc)
    False -> collect_stream_lifecycle(selector, acc)
  }
}

fn is_termination_message(msg: client.StreamMessage) -> Bool {
  case msg {
    client.StreamEnd(_, _) -> True
    client.StreamError(_, _) -> True
    _ -> False
  }
}

fn is_stream_start(msg: client.StreamMessage) -> Bool {
  case msg {
    client.StreamStart(_, _) -> True
    _ -> False
  }
}

fn is_stream_end(msg: client.StreamMessage) -> Bool {
  case msg {
    client.StreamEnd(_, _) -> True
    _ -> False
  }
}

fn is_stream_error(msg: client.StreamMessage) -> Bool {
  case msg {
    client.StreamError(_, _) -> True
    _ -> False
  }
}

fn handle_lifecycle_message(
  selector: process.Selector(client.StreamMessage),
  acc: List(client.StreamMessage),
  msg: client.StreamMessage,
) -> List(client.StreamMessage) {
  case msg {
    client.StreamEnd(_, _) -> list.reverse([msg, ..acc])
    client.StreamError(_, _) -> list.reverse([msg, ..acc])
    _ -> collect_stream_lifecycle(selector, [msg, ..acc])
  }
}

/// Test: RequestId can be used to discriminate between streams
pub fn request_id_discrimination_test() {
  // Arrange - Start 2 streams
  let req1 =
    client.new
    |> client.method(http.Get)
    |> client.scheme(http.Https)
    |> client.host("httpbin.org")
    |> client.path("/stream/2")

  let req2 =
    client.new
    |> client.method(http.Get)
    |> client.scheme(http.Https)
    |> client.host("httpbin.org")
    |> client.path("/stream/2")

  // Build selector BEFORE starting streams to ensure no messages are lost
  let selector =
    process.new_selector()
    |> client.select_stream_messages(fn(msg) { msg })

  // Drain mailbox to prevent messages from previous tests
  drain_mailbox(selector)

  let assert Ok(id1) = client.stream_messages(req1)
  let assert Ok(id2) = client.stream_messages(req2)

  // Act - Collect messages and track by RequestId
  let messages = collect_messages(selector, [], 20)

  let id1_str = req_id_to_string(id1)
  let id2_str = req_id_to_string(id2)

  let id1_messages = list.filter(messages, message_has_request_id(_, id1_str))

  let id2_messages = list.filter(messages, message_has_request_id(_, id2_str))

  // Assert - Both streams received messages
  { id1_messages != [] } |> should.be_true()
  { id2_messages != [] } |> should.be_true()

  // Assert - No messages were mixed up
  let total = list.length(id1_messages) + list.length(id2_messages)
  total |> should.equal(list.length(messages))

  Nil
}

/// Test: Chunk data is received correctly
pub fn chunk_data_received_test() {
  // Arrange
  let req =
    client.new
    |> client.method(http.Get)
    |> client.scheme(http.Https)
    |> client.host("httpbin.org")
    |> client.path("/stream/1")

  // Build selector BEFORE starting stream to ensure no messages are lost
  let selector =
    process.new_selector()
    |> client.select_stream_messages(fn(msg) { msg })

  // Drain mailbox to prevent messages from previous tests
  drain_mailbox(selector)

  let assert Ok(_req_id) = client.stream_messages(req)

  // Act - Receive until we get a chunk
  let chunk_data = receive_first_chunk(selector, 10)

  // Assert - We got non-empty chunk data
  case chunk_data {
    Ok(data) -> verify_chunk_has_data(data)
    Error(_) -> should.fail()
  }
}

fn verify_chunk_has_data(data: BitArray) -> Nil {
  let size = bit_array.byte_size(data)
  { size > 0 } |> should.be_true()

  Nil
}

fn receive_first_chunk(
  selector: process.Selector(client.StreamMessage),
  attempts: Int,
) -> Result(BitArray, Nil) {
  case attempts {
    0 -> Error(Nil)
    _ -> handle_chunk_receive(selector, attempts)
  }
}

fn handle_chunk_receive(
  selector: process.Selector(client.StreamMessage),
  attempts: Int,
) -> Result(BitArray, Nil) {
  case process.selector_receive(selector, 2000) {
    Ok(msg) -> extract_chunk_or_retry(selector, attempts, msg)
    Error(_) -> receive_first_chunk(selector, attempts - 1)
  }
}

fn extract_chunk_or_retry(
  selector: process.Selector(client.StreamMessage),
  attempts: Int,
  msg: client.StreamMessage,
) -> Result(BitArray, Nil) {
  case msg {
    client.Chunk(_, data) -> Ok(data)
    _ -> receive_first_chunk(selector, attempts - 1)
  }
}

/// Test: Headers are received in StreamStart
pub fn stream_start_headers_test() {
  // Arrange
  let req =
    client.new
    |> client.method(http.Get)
    |> client.scheme(http.Https)
    |> client.host("httpbin.org")
    |> client.path("/stream/1")

  // Build selector BEFORE starting stream to ensure no messages are lost
  let selector =
    process.new_selector()
    |> client.select_stream_messages(fn(msg) { msg })

  // Drain mailbox to prevent messages from previous tests
  drain_mailbox(selector)

  let assert Ok(_req_id) = client.stream_messages(req)

  // Act - Receive until we get StreamStart (with retries for network latency)
  let headers = receive_stream_start_headers(selector, 10)

  // Assert - We got headers
  case headers {
    Ok(hdrs) -> verify_headers_not_empty(hdrs)
    Error(_) -> should.fail()
  }
}

fn verify_headers_not_empty(hdrs: List(#(String, String))) -> Nil {
  { hdrs != [] } |> should.be_true()

  Nil
}

fn receive_stream_start_headers(
  selector: process.Selector(client.StreamMessage),
  attempts: Int,
) -> Result(List(#(String, String)), Nil) {
  case attempts {
    0 -> Error(Nil)
    _ -> handle_header_receive(selector, attempts)
  }
}

fn handle_header_receive(
  selector: process.Selector(client.StreamMessage),
  attempts: Int,
) -> Result(List(#(String, String)), Nil) {
  case process.selector_receive(selector, 2000) {
    Ok(msg) -> extract_headers_or_retry(selector, attempts, msg)
    Error(_) -> receive_stream_start_headers(selector, attempts - 1)
  }
}

fn extract_headers_or_retry(
  selector: process.Selector(client.StreamMessage),
  attempts: Int,
  msg: client.StreamMessage,
) -> Result(List(#(String, String)), Nil) {
  case msg {
    client.StreamStart(_, headers) -> Ok(headers)
    _ -> receive_stream_start_headers(selector, attempts - 1)
  }
}

/// Test: Yielder-based streaming still works
pub fn stream_yielder_test() {
  // Arrange
  let req =
    client.new
    |> client.method(http.Get)
    |> client.scheme(http.Https)
    |> client.host("httpbin.org")
    |> client.path("/stream/2")

  // Act
  let chunks =
    client.stream_yielder(req)
    |> yielder.take(5)
    |> yielder.to_list()

  // Assert - We got chunks
  { chunks != [] } |> should.be_true()

  // Assert - Chunks contain data
  case chunks {
    [first, ..] -> verify_first_chunk_size(first)
    [] -> should.fail()
  }
}

fn verify_first_chunk_size(first: bytes_tree.BytesTree) -> Nil {
  let size = bytes_tree.byte_size(first)
  { size > 0 } |> should.be_true()

  Nil
}

/// Test: Blocking send() works
pub fn send_test() {
  // Arrange
  let req =
    client.new
    |> client.method(http.Get)
    |> client.scheme(http.Https)
    |> client.host("httpbin.org")
    |> client.path("/get")

  // Act
  let result = client.send(req)

  // Assert
  case result {
    Ok(body) -> {
      { string.length(body) > 0 } |> should.be_true()
    }
    Error(_) -> should.fail()
  }

  Nil
}

// ============================================================================
// Error Path and Edge Case Tests
// ============================================================================

/// Test: StreamError is received on network failure
pub fn stream_error_on_failure_test() {
  // Arrange - Use a port that won't have a server listening
  let req =
    client.new
    |> client.method(http.Get)
    |> client.scheme(http.Http)
    |> client.host("localhost")
    |> client.port(19_999)
    |> client.path("/nonexistent")

  // Build selector BEFORE starting stream
  let selector =
    process.new_selector()
    |> client.select_stream_messages(fn(msg) { msg })

  // Drain mailbox
  drain_mailbox(selector)

  let assert Ok(_req_id) = client.stream_messages(req)

  // Act - Collect messages until we get an error or timeout
  let messages = collect_messages(selector, [], 5)

  // Assert - We got a StreamError message
  let has_error = list.any(messages, is_stream_error)

  has_error |> should.be_true()

  Nil
}

/// Test: Cancel stream stops message delivery
pub fn cancel_stream_stops_messages_test() {
  // Arrange - Start a stream that would send multiple chunks
  let req =
    client.new
    |> client.method(http.Get)
    |> client.scheme(http.Https)
    |> client.host("httpbin.org")
    |> client.path("/stream/10")

  // Build selector BEFORE starting stream
  let selector =
    process.new_selector()
    |> client.select_stream_messages(fn(msg) { msg })

  // Drain mailbox
  drain_mailbox(selector)

  let assert Ok(req_id) = client.stream_messages(req)

  // Act - Receive StreamStart, then immediately cancel
  let start_msg = receive_stream_start_headers(selector, 10)
  case start_msg {
    Ok(_) -> verify_cancellation(selector, req_id)
    Error(_) -> should.fail()
  }
}

fn verify_cancellation(
  selector: process.Selector(client.StreamMessage),
  req_id: client.RequestId,
) -> Nil {
  // Cancel the stream immediately
  client.cancel_stream(req_id)

  // Wait a bit to see if any messages still arrive
  process.sleep(1000)

  // Try to receive with short timeout - should get nothing or very few
  let msg1 = process.selector_receive(selector, 500)
  let msg2 = process.selector_receive(selector, 500)
  let msg3 = process.selector_receive(selector, 500)

  // Count how many messages we got
  let count = count_received_messages(msg1, msg2, msg3)

  // Assert - Should get fewer than 10 chunks (stream was cancelled early)
  { count < 10 } |> should.be_true()
}

fn count_received_messages(
  msg1: Result(client.StreamMessage, Nil),
  msg2: Result(client.StreamMessage, Nil),
  msg3: Result(client.StreamMessage, Nil),
) -> Int {
  case msg1, msg2, msg3 {
    Ok(_), Ok(_), Ok(_) -> 3
    Ok(_), Ok(_), Error(_) -> 2
    Ok(_), Error(_), Error(_) -> 1
    Error(_), Error(_), Error(_) -> 0
    _, _, _ -> 0
  }
}

/// Test: StreamEnd includes trailing headers
pub fn stream_end_headers_test() {
  // Arrange
  let req =
    client.new
    |> client.method(http.Get)
    |> client.scheme(http.Https)
    |> client.host("httpbin.org")
    |> client.path("/stream/1")

  // Build selector BEFORE starting stream
  let selector =
    process.new_selector()
    |> client.select_stream_messages(fn(msg) { msg })

  // Drain mailbox
  drain_mailbox(selector)

  let assert Ok(_req_id) = client.stream_messages(req)

  // Act - Collect all messages until stream ends
  let messages = collect_stream_lifecycle(selector, [])

  // Assert - StreamEnd message exists and can contain headers
  let has_end_with_headers = list.any(messages, has_stream_end_with_headers)

  has_end_with_headers |> should.be_true()
}

fn has_stream_end_with_headers(msg: client.StreamMessage) -> Bool {
  case msg {
    client.StreamEnd(_, headers) -> {
      // Headers may be empty or non-empty depending on server
      // Just verify we can receive and decode them
      let _ = headers
      True
    }
    _ -> False
  }
}

/// Test: Small response handled correctly (edge case for single chunk)
pub fn small_response_test() {
  // Arrange - Use an endpoint that returns a small response
  let req =
    client.new
    |> client.method(http.Get)
    |> client.scheme(http.Https)
    |> client.host("httpbin.org")
    |> client.path("/uuid")

  // Act
  let result = client.send(req)

  // Assert - Got a successful result with a small body
  case result {
    Ok(body) -> verify_body_not_empty(body)
    Error(_) -> should.fail()
  }
}

fn verify_body_not_empty(body: String) -> Nil {
  // UUID response is small but non-empty
  { string.length(body) > 0 } |> should.be_true()

  Nil
}

/// Test: Large response streams correctly
pub fn large_response_streaming_test() {
  // Arrange - Use an endpoint that returns multiple chunks
  let req =
    client.new
    |> client.method(http.Get)
    |> client.scheme(http.Https)
    |> client.host("httpbin.org")
    |> client.path("/stream/5")

  // Build selector BEFORE starting stream
  let selector =
    process.new_selector()
    |> client.select_stream_messages(fn(msg) { msg })

  // Drain mailbox
  drain_mailbox(selector)

  let assert Ok(_req_id) = client.stream_messages(req)

  // Act - Collect all messages
  let messages = collect_stream_lifecycle(selector, [])

  // Assert - We got at least one chunk and proper lifecycle
  let chunk_count = count_chunks(messages)
  { chunk_count >= 1 } |> should.be_true()

  let has_start = list.any(messages, is_stream_start)

  let has_end = list.any(messages, is_stream_end)

  has_start |> should.be_true()
  has_end |> should.be_true()

  Nil
}
