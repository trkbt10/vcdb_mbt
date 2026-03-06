# http

HTTP routing layer for vcdb REST API.

## Types

- `HttpRequest`: HTTP request with method, path, headers, body
- `HttpResponse`: HTTP response with status, headers, body
- `Router[S]`: Routes requests to gateway handlers

## Usage

```moonbit
let router : Router[@storage.MemoryStorage] = Router::new()
let request = HttpRequest::new("POST", "/collections/test/points/search", body~)
let response = router.route(request)
```

## Response Helpers

- `HttpResponse::ok(body)`: 200 OK
- `HttpResponse::created(body)`: 201 Created
- `HttpResponse::bad_request(body)`: 400 Bad Request
- `HttpResponse::not_found(body)`: 404 Not Found
- `HttpResponse::internal_error(body)`: 500 Internal Server Error
