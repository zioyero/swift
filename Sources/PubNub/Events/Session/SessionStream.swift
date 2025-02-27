//
//  SessionStream.swift
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

/// A stream of `Session` events
public protocol SessionStream: EventStreamReceiver {
  // URLRequest Building
  func emitRequest(_ request: Request, didCreate urlRequest: URLRequest)
  func emitRequest(_ request: Request, didFailToCreateURLRequestWith error: Error)

  // URLSessionTask States
  func emitRequest(_ request: Request, didCreate task: URLSessionTask)
  func emitRequest(_ request: Request, didResume task: URLSessionTask)
  func emitRequest(_ request: Request, didCancel task: URLSessionTask)
  func emitRequest(_ request: Request, didComplete task: URLSessionTask)
  func emitRequest(_ request: Request, didComplete task: URLSessionTask, with error: Error)

  // Request States
  func emitRequestDidResume(_ request: Request)
  func emitRequestDidFinish(_ request: Request)
  func emitRequestDidCancel(_ request: Request)
  func emitRequestIsRetrying(_ request: Request)

  // Request Mutator
  func emitRequest(_ request: Request, didMutate initialURLRequest: URLRequest, to mutatedURLRequest: URLRequest)
  func emitRequest(_ request: Request, didFailToMutate initialURLRequest: URLRequest, with error: Error)

  // URLSessionDelegate
  func emitURLSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data)
  func emitURLSession(_ session: URLSession, task: URLSessionTask, didCompleteWith error: Error?)
  func emitURLSession(_ session: URLSession, didBecomeInvalidWith error: Error?)
}

public extension SessionStream {
  // no-op body allows protocol methods to be `optional` without using @objc
  func emitRequest(_: Request, didCreate _: URLRequest) { /* no-op */ }
  func emitRequest(_: Request, didFailToCreateURLRequestWith _: Error) { /* no-op */ }

  func emitRequest(_: Request, didCreate _: URLSessionTask) { /* no-op */ }
  func emitRequest(_: Request, didResume _: URLSessionTask) { /* no-op */ }
  func emitRequest(_: Request, didCancel _: URLSessionTask) { /* no-op */ }
  func emitRequest(_: Request, didComplete _: URLSessionTask) { /* no-op */ }
  func emitRequest(_: Request, didComplete _: URLSessionTask, with _: Error) { /* no-op */ }

  func emitRequestDidResume(_: Request) { /* no-op */ }
  func emitRequestDidFinish(_: Request) { /* no-op */ }
  func emitRequestDidCancel(_: Request) { /* no-op */ }
  func emitRequestIsRetrying(_: Request) { /* no-op */ }

  func emitRequest(_: Request, didMutate _: URLRequest, to _: URLRequest) { /* no-op */ }
  func emitRequest(_: Request, didFailToMutate _: URLRequest, with _: Error) { /* no-op */ }

//  func emitDidDecode(_: Response<Data>) { /* no-op */ }
//  func emitFailedToDecode(_: Response<Data>, with _: Error) { /* no-op */ }

  // URLSessionDelegate
  func emitURLSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive _: Data) { /* no-op */ }
  func emitURLSession(_: URLSession, task _: URLSessionTask, didCompleteWith _: Error?) { /* no-op */ }
  func emitURLSession(_: URLSession, didBecomeInvalidWith _: Error?) { /* no-op */ }
}

public final class MultiplexSessionStream: SessionStream, Hashable {
  public let queue: DispatchQueue
  public let uuid: UUID
  public let streams: [SessionStream]

  public init(_ streams: [SessionStream], queue: DispatchQueue? = nil) {
    uuid = UUID()
    self.streams = streams
    self.queue = queue ?? DispatchQueue(label: "org.pubnub.complexSessionStream", qos: .default)
  }

  func performEvent(_ closure: @escaping (SessionStream) -> Void) {
    queue.async {
      for stream in self.streams {
        stream.queue.async { closure(stream) }
      }
    }
  }

  // Hashable
  public static func == (lhs: MultiplexSessionStream, rhs: MultiplexSessionStream) -> Bool {
    return lhs.uuid == rhs.uuid
  }

  public func emitRequest(_ request: Request, didCreate urlRequest: URLRequest) {
    performEvent { $0.emitRequest(request, didCreate: urlRequest) }
  }

  public func emitRequest(_ request: Request, didFailToCreateURLRequestWith error: Error) {
    performEvent { $0.emitRequest(request, didFailToCreateURLRequestWith: error) }
  }

  public func emitRequest(_ request: Request, didCreate task: URLSessionTask) {
    performEvent { $0.emitRequest(request, didCreate: task) }
  }

  public func emitRequest(_ request: Request, didResume task: URLSessionTask) {
    performEvent { $0.emitRequest(request, didResume: task) }
  }

  public func emitRequest(_ request: Request, didCancel task: URLSessionTask) {
    performEvent { $0.emitRequest(request, didCancel: task) }
  }

  public func emitRequest(_ request: Request, didComplete task: URLSessionTask) {
    performEvent { $0.emitRequest(request, didComplete: task) }
  }

  public func emitRequest(_ request: Request, didComplete task: URLSessionTask, with error: Error) {
    performEvent { $0.emitRequest(request, didComplete: task, with: error) }
  }

  public func emitRequestDidResume(_ request: Request) {
    performEvent { $0.emitRequestDidResume(request) }
  }

  public func emitRequestDidFinish(_ request: Request) {
    performEvent { $0.emitRequestDidFinish(request) }
  }

  public func emitRequestDidCancel(_ request: Request) {
    performEvent { $0.emitRequestDidCancel(request) }
  }

  public func emitRequestIsRetrying(_ request: Request) {
    performEvent { $0.emitRequestIsRetrying(request) }
  }

  public func emitRequest(
    _ request: Request,
    didMutate initialURLRequest: URLRequest,
    to mutatedURLRequest: URLRequest
  ) {
    performEvent { $0.emitRequest(request, didMutate: initialURLRequest, to: mutatedURLRequest) }
  }

  public func emitRequest(_ request: Request, didFailToMutate initialURLRequest: URLRequest, with error: Error) {
    performEvent { $0.emitRequest(request, didFailToMutate: initialURLRequest, with: error) }
  }

  public func emitURLSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    performEvent { $0.emitURLSession(session, dataTask: dataTask, didReceive: data) }
  }

  public func emitURLSession(_ session: URLSession, task: URLSessionTask, didCompleteWith error: Error?) {
    performEvent { $0.emitURLSession(session, task: task, didCompleteWith: error) }
  }

  public func emitURLSession(_ session: URLSession, didBecomeInvalidWith error: Error?) {
    performEvent { $0.emitURLSession(session, didBecomeInvalidWith: error) }
  }
}

final class SessionListener: SessionStream, Hashable {
  public let uuid: UUID
  public let queue: DispatchQueue

  public init(queue: DispatchQueue = .main) {
    uuid = UUID()
    self.queue = queue
  }

  public static func == (lhs: SessionListener, rhs: SessionListener) -> Bool {
    return lhs.uuid == rhs.uuid
  }

  // Closures
  var didCreateURLRequest: ((Request, URLRequest) -> Void)?
  var didFailToCreateURLRequestWithError: ((Request, Error) -> Void)?

  var didCreateTask: ((Request, URLSessionTask) -> Void)?
  var didResumeTask: ((Request, URLSessionTask) -> Void)?
  var didCancelTask: ((Request, URLSessionTask) -> Void)?
  var didCompleteTask: ((Request, URLSessionTask) -> Void)?
  var didCompleteTaskWithError: ((Request, URLSessionTask, Error) -> Void)?

  var didResumeRequest: ((Request) -> Void)?
  var didFinishRequest: ((Request) -> Void)?
  var didCancelRequest: ((Request) -> Void)?
  var didRetryRequest: ((Request) -> Void)?

  var didMutateRequest: ((Request, URLRequest, URLRequest) -> Void)?
  var didFailToMutateRequest: ((Request, URLRequest, Error) -> Void)?

  var sessionTaskDidReceiveData: ((URLSession, URLSessionDataTask, Data) -> Void)?
  var sessionTaskDidComplete: ((URLSession, URLSessionTask, Error?) -> Void)?
  var sessionDidBecomeInvalidated: ((URLSession, Error?) -> Void)?

  // URLRequest Building
  func emitRequest(_ request: Request, didCreate urlRequest: URLRequest) {
    queue.async { self.didCreateURLRequest?(request, urlRequest) }
  }

  func emitRequest(_ request: Request, didFailToCreateURLRequestWith error: Error) {
    queue.async { self.didFailToCreateURLRequestWithError?(request, error) }
  }

  // URLSessionTask States
  func emitRequest(_ request: Request, didCreate task: URLSessionTask) {
    queue.async { self.didCreateTask?(request, task) }
  }

  func emitRequest(_ request: Request, didResume task: URLSessionTask) {
    queue.async { self.didResumeTask?(request, task) }
  }

  func emitRequest(_ request: Request, didCancel task: URLSessionTask) {
    queue.async { self.didCancelTask?(request, task) }
  }

  func emitRequest(_ request: Request, didComplete task: URLSessionTask) {
    queue.async { self.didCompleteTask?(request, task) }
  }

  func emitRequest(_ request: Request, didComplete task: URLSessionTask, with error: Error) {
    queue.async { self.didCompleteTaskWithError?(request, task, error) }
  }

  // Request States
  func emitRequestDidResume(_ request: Request) {
    queue.async { self.didResumeRequest?(request) }
  }

  func emitRequestDidFinish(_ request: Request) {
    queue.async { self.didFinishRequest?(request) }
  }

  func emitRequestDidCancel(_ request: Request) {
    queue.async { self.didCancelRequest?(request) }
  }

  func emitRequestIsRetrying(_ request: Request) {
    queue.async { self.didRetryRequest?(request) }
  }

  // Request Mutator
  func emitRequest(_ request: Request, didMutate initialURLRequest: URLRequest, to mutatedURLRequest: URLRequest) {
    queue.async { self.didMutateRequest?(request, initialURLRequest, mutatedURLRequest) }
  }

  func emitRequest(_ request: Request, didFailToMutate initialURLRequest: URLRequest, with error: Error) {
    queue.async { self.didFailToMutateRequest?(request, initialURLRequest, error) }
  }

  // URLSessionDelegate
  func emitURLSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    queue.async { self.sessionTaskDidReceiveData?(session, dataTask, data) }
  }

  func emitURLSession(_ session: URLSession, task: URLSessionTask, didCompleteWith error: Error?) {
    queue.async { self.sessionTaskDidComplete?(session, task, error) }
  }

  func emitURLSession(_ session: URLSession, didBecomeInvalidWith error: Error?) {
    queue.async { self.sessionDidBecomeInvalidated?(session, error) }
  }
}
