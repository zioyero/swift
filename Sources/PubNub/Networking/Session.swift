//
//  Session.swift
//
//  PubNub Real-time Cloud-Hosted Push API and Push Notification Client Frameworks
//  Copyright © 2019 PubNub Inc.
//  https://www.pubnub.com/
//  https://www.pubnub.com/terms
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

// MARK: - PubNub Networking

/// An object that coordinates a group of related network data transfer tasks.
public final class Session {
  /// The unique identifier for this object
  public let sessionID: UUID = UUID()
  /// The underlying `URLSession` used to execute the network tasks
  public let session: URLSessionReplaceable
  /// The dispatch queue used to execute session operations
  public let sessionQueue: DispatchQueue
  /// The dispatch queue used to execute request operations
  public let requestQueue: DispatchQueue
  /// The state that tracks the validity of the underlying `URLSessionReplaceable`
  let invalidationState = AtomicInt(0)
  /// The delegate that receives incoming network transmissions
  weak var delegate: SessionDelegate?
  /// The event stream that session activity status will emit to
  let sessionStream: SessionStream?
  /// The `RequestOperator` that is attached to every request
  var defaultRequestOperator: RequestOperator?
  /// The collection of associations between `URLSessionTask` and their corresponding `Request`
  var taskToRequest: [URLSessionTask: Request] = [:]

  public init(
    session: URLSessionReplaceable,
    delegate: SessionDelegate,
    sessionQueue: DispatchQueue,
    requestQueue: DispatchQueue? = nil,
    sessionStream: SessionStream? = nil
  ) {
    precondition(session.delegateQueue.underlyingQueue === sessionQueue,
                 "Session.sessionQueue must be the same DispatchQueue used as the URLSession.delegate underlyingQueue")

    self.session = session
    self.sessionQueue = sessionQueue
    self.requestQueue = requestQueue ?? DispatchQueue(label: "com.pubnub.session.requestQueue", target: sessionQueue)

    self.delegate = delegate
    self.sessionStream = sessionStream

    PubNub.log.debug("Session created \(sessionID)")

    delegate.sessionBridge = self
  }

  public convenience init(
    configuration: URLSessionConfiguration = .ephemeral,
    delegate: SessionDelegate = SessionDelegate(),
    sessionQueue: DispatchQueue = DispatchQueue(label: "com.pubnub.session.sessionQueue"),
    requestQueue: DispatchQueue? = nil,
    sessionStream: SessionStream? = nil
  ) {
    let delegateQueue = OperationQueue(maxConcurrentOperationCount: 1,
                                       underlyingQueue: sessionQueue,
                                       name: "org.pubnub.httpClient.URLSessionReplaceableDelegate")

    let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: delegateQueue)
    session.sessionDescription = "Underlying URLSession for: com.pubnub.session"

    self.init(session: session,
              delegate: delegate,
              sessionQueue: sessionQueue,
              requestQueue: requestQueue,
              sessionStream: sessionStream)
  }

  deinit {
    PubNub.log.debug("Session Destoryed \(sessionID) with active requests \(taskToRequest.values.map { $0.requestID })")

    taskToRequest.values.forEach {
      $0.cancel(PubNubError(.sessionDeinitialized, endpoint: $0.router.endpoint.category))
    }

    invalidateAndCancel()
  }

  // MARK: - Self Operators

  /// The method used to set the default `RequestOperator`
  ///
  /// - parameter requestOperator: The default `RequestOperator`
  /// - returns: This `Session` object
  public func usingDefault(requestOperator: RequestOperator?) -> Self {
    defaultRequestOperator = requestOperator
    return self
  }

  // MARK: - Perform Request

  /// Creates and performs a request using the provided router
  ///
  /// - parameters:
  ///   -  with: The `Router` used to create the `Request`
  ///   -  requestOperator: The operator specific to this `Request`
  /// - returns: This created `Request`
  public func request(
    with router: Router,
    requestOperator: RequestOperator? = nil
  ) -> Request {
    let request = Request(with: router,
                          requestQueue: sessionQueue,
                          sessionStream: sessionStream,
                          requestOperator: requestOperator,
                          delegate: self,
                          createdBy: sessionID)

    perform(request)

    return request
  }

  // MARK: Internal Methods

  func perform(_ request: Request) {
    requestQueue.async {
      // Ensure that the request hasn't been cancelled
      if request.isCancelled { return }

      self.perform(request, urlRequest: request.router)
    }
  }

  func perform(_ request: Request, urlRequest convertible: URLRequestConvertible) {
    // Perform the request.  (SessionDelegate will emit the response)
    let urlRequest: URLRequest

    // Create the URLRequest
    switch convertible.asURLRequest {
    case let .success(convertURLRequest):
      urlRequest = convertURLRequest
      sessionQueue.async {
        request.didCreate(convertURLRequest)
      }
    case let .failure(error):
      sessionQueue.async {
        request.didFailToCreateURLRequest(with: error)
      }
      return
    }

    // Ensure that the request hasn't been cancelled
    if request.isCancelled { return }

    // Perform any provided request mutations
    if let mutator = self.mutator(for: request) {
      mutator.mutate(urlRequest, for: self) { [weak self] result in
        switch result {
        case let .success(mutatedRequest):
          self?.sessionQueue.async {
            request.didMutate(urlRequest, to: mutatedRequest)
            self?.didCreateURLRequest(urlRequest, for: request)
          }
        case let .failure(error):
          self?.sessionQueue.async {
            request.didFailToMutate(urlRequest, with: error)
          }
        }
      }
    } else {
      sessionQueue.async {
        self.didCreateURLRequest(urlRequest, for: request)
      }
    }
  }

  /// True if the underlying session is invalidated and can no longer perform requests
  public internal(set) var isInvalidated: Bool {
    get {
      return invalidationState.isEqual(to: 1)
    }
    set {
      invalidationState.bitwiseOrAssignemnt(newValue ? 1 : 0)
    }
  }

  func didCreateURLRequest(_ urlRequest: URLRequest, for request: Request) {
    if request.isCancelled { return }

    // Leak inside URLSession; passing in copy to avoid passing in managed objects
    let urlRequestCopy = urlRequest

    // URLSession doesn't provide a way to check if it's invalidated,
    // so we lock to avoid crashes from creating tasks while invalidated
    if !isInvalidated {
      let task = session.dataTask(with: urlRequestCopy)
      taskToRequest[task] = request
      request.didCreate(task)

      updateStatesForTask(task, request: request)
    } else {
      PubNub.log.warn("Attempted to create task from invalidated session: \(sessionID)")
    }
  }

  func updateStatesForTask(_ task: URLSessionTask, request: Request) {
    request.withTaskState { atomicState in
      switch atomicState {
      case .initialized:
        sessionQueue.async { request.resume() }
      case .resumed:
        // URLDataTasks cannot be 'resumed' after starting, but this is called during a retry
        task.resume()
        sessionQueue.async { request.didResume(task) }
      case .cancelled:
        task.cancel()
        sessionQueue.async { request.didCancel(task) }
      case .finished:
        // Do nothing
        break
      }
    }
  }

  func mutator(for request: Request) -> RequestMutator? {
    if let requestOperator = request.requestOperator, let sessionOperator = defaultRequestOperator {
      return MultiplexRequestOperator(operators: [requestOperator, sessionOperator])
    } else {
      return request.requestOperator ?? defaultRequestOperator
    }
  }

  func retrier(for request: Request) -> RequestRetrier? {
    if let requestOperator = request.requestOperator, let sessionOperator = defaultRequestOperator {
      return MultiplexRequestOperator(operators: [requestOperator, sessionOperator])
    } else {
      return request.requestOperator ?? defaultRequestOperator
    }
  }

  /// Cancels all requests on a given `Endpoint` returning the provided error reason
  ///
  /// - Parameters:
  ///   - reason: The reason for the cancellation
  ///   - for: The endpoint whose requests will be cancelled
  public func cancelAllTasks(_ reason: PubNubError.Reason, for endpoint: Endpoint.Category = .subscribe) {
    sessionQueue.async { [weak self] in
      self?.taskToRequest.forEach { task, request in
        if request.router.endpoint.category == endpoint {
          request.cancellationReason = reason
          PubNub.log.debug("Cancelling Task for request \(request.requestID)")
          task.cancel()
        }
      }
    }
  }

  /// Cancels all outstanding tasks and then invalidates the session.
  ///
  /// Once invalidated, references to the delegate and callback objects are broken.
  /// After invalidation, session objects cannot be reused.
  /// - Important: Calling this method on the session returned by the shared method has no effect.
  public func invalidateAndCancel() {
    // Ensure that we lock out task creation prior to invalidating
    isInvalidated = true

    session.invalidateAndCancel()
  }
}

// MARK: - RequestDelegate

extension Session: RequestDelegate {
  public func retryResult(
    for request: Request,
    dueTo error: Error,
    andPrevious _: Error?,
    completion: @escaping (Result<TimeInterval, Error>) -> Void
  ) {
    // Immediately return error if we don't have any retry logic
    guard let retrier = retrier(for: request) else {
      sessionQueue.async { completion(.failure(error)) }
      return
    }

    PubNub.log.info("Retrying request \(request.requestID) due to error \(error)")

    retrier.retry(request, for: self, dueTo: error) { [weak self] retryResult in
      self?.sessionQueue.async {
        completion(retryResult)
      }
    }
  }

  public func retryRequest(_ request: Request, withDelay timeDelay: TimeInterval?) {
    sessionQueue.async {
      let retry: () -> Void = {
        if request.isCancelled { return }

        request.prepareForRetry()

        self.perform(request)
      }

      if let retryDelay = timeDelay {
        self.sessionQueue.asyncAfter(deadline: .now() + retryDelay) {
          retry()
        }
      } else {
        retry()
      }
    }
  }
}
