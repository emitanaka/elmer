# Currently performing chat request is not generic as there appears to
# be sufficiently genericity elsewhere to handle the API variations.
# We will recconsider this in the future if necessary.
chat_perform <- function(provider,
                         mode = c("value", "stream", "async-stream", "async-value"),
                         turns,
                         tools = list(),
                         extra_args = list()) {

  mode <- arg_match(mode)
  stream <- mode %in% c("stream", "async-stream")

  req <- chat_request(
    provider = provider,
    turns = turns,
    tools = tools,
    stream = stream,
    extra_args = extra_args
  )

  switch(mode,
    "value" = chat_perform_value(provider, req),
    "stream" = chat_perform_stream(provider, req),
    "async-value" = chat_perform_async_value(provider, req),
    "async-stream" = chat_perform_async_stream(provider, req)
  )
}

chat_perform_value <- function(provider, req) {
  resp_body_json(req_perform(req))
}

on_load(chat_perform_stream <- coro::generator(function(provider, req) {
  resp <- req_perform_connection(req)
  on.exit(close(resp))
  reg.finalizer(environment(), function(e) { close(resp) }, onexit = FALSE)

  repeat {
    event <- resp_stream_sse(resp)
    data <- stream_parse(provider, event)
    if (is.null(data)) {
      break
    } else {
      yield(data)
    }
  }

  # Work around https://github.com/r-lib/coro/issues/51
  if (FALSE) {
    yield(NULL)
  }
}))

chat_perform_async_value <- function(provider, req) {
  promises::then(req_perform_promise(req), resp_body_json)
}

on_load(chat_perform_async_stream <- coro::async_generator(function(provider, req, polling_interval_secs = 0.1) {
  resp <- req_perform_connection(req, blocking = FALSE)
  on.exit(close(resp))
  # TODO: Investigate if this works with async generators
  # reg.finalizer(environment(), function(e) { close(resp) }, onexit = FALSE)

  repeat {
    event <- resp_stream_sse(resp)
    if (is.null(event) && isIncomplete(resp$body)) {
      await(coro::async_sleep(polling_interval_secs))
      next
    }

    data <- stream_parse(provider, event)
    if (is.null(data)) {
      break
    } else {
      yield(data)
    }
  }

  # Work around https://github.com/r-lib/coro/issues/51
  if (FALSE) {
    yield(NULL)
  }
}))
