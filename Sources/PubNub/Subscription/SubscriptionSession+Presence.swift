//
//  SubscriptionSession+Presence.swift
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

extension SubscriptionSession {
  // MARK: - Heartbeat Loop

  func registerHeartbeatTimer() {
    presenceTimer?.invalidate()

    if configuration.heartbeatInterval == 0 {
      return
    }

    let timer = Timer(fireAt: Date(timeIntervalSinceNow: Double(configuration.heartbeatInterval)),
                      interval: 0.0,
                      target: self,
                      selector: #selector(peformHeartbeatLoop),
                      userInfo: nil,
                      repeats: false)

    RunLoop.main.add(timer, forMode: .common)
    presenceTimer = timer
  }

  func stopHeartbeatTimer() {
    presenceTimer?.invalidate()
  }

  /// The amount of seconds until the next attempted presence heartbeat
  var nextPresenceHeartbeat: TimeInterval {
    return presenceTimer?.fireDate.timeIntervalSinceNow ?? 0.0
  }

  @objc func peformHeartbeatLoop() {
    // Get non-presence channels and groups
    let (channels, groups) = internalState.lockedRead { ($0.subscribedChannels, $0.subscribedGroups) }

    if channels.isEmpty, groups.isEmpty {
      return
    }

    // Perform Heartbeat
    let router = PubNubRouter(configuration: configuration,
                              endpoint: .heartbeat(channels: channels,
                                                   groups: groups,
                                                   presenceTimeout: configuration.durationUntilTimeout))

    networkSession
      .request(with: router, requestOperator: configuration.automaticRetry)
      .validate()
      .response(decoder: GenericServiceResponseDecoder()) { [weak self] result in
        switch result {
        case .success:
          // If the connection is active register a new heartbeat otherwise stop the timer
          self?.connectionStatus.isActive ?? false ? self?.registerHeartbeatTimer() : self?.stopHeartbeatTimer()
        case .failure:
          self?.stopHeartbeatTimer()
        }
      }

    // Get state
    registerHeartbeatTimer()
  }

  // MARK: - Leave

  public func presenceLeave(
    for _: String,
    on channels: [String],
    and groups: [String],
    completion: @escaping (Result<Bool, Error>) -> Void
  ) {
    let router = PubNubRouter(configuration: configuration,
                              endpoint: .leave(channels: channels, groups: groups))

    networkSession
      .request(with: router, requestOperator: configuration.automaticRetry)
      .validate()
      .response(decoder: GenericServiceResponseDecoder()) { result in
        switch result {
        case .success:
          completion(.success(true))
        case let .failure(error):
          completion(.failure(error))
        }
      }
  }

  // MARK: - Presence State

  public func getPresenceState(
    for uuid: String,
    on channels: [String],
    and groups: [String],
    completion: @escaping (Result<[String: [String: AnyJSON]], Error>) -> Void
  ) {
    let router = PubNubRouter(configuration: configuration,
                              endpoint: .getPresenceState(uuid: uuid, channels: channels, groups: groups))

    networkSession
      .request(with: router, requestOperator: configuration.automaticRetry)
      .validate()
      .response(decoder: AnyJSONResponseDecoder()) { [weak self] result in

        completion(result.flatMap { response in
          let normalizedState: [String: [String: AnyJSON]]

          do {
            if let singleChannel = try? response.payload.decode(SinglePresenceStatePayload.self) {
              normalizedState = singleChannel.normalizedPayload
            } else {
              let multiChannel = try response.payload.decode(MultiPresenceStatePayload.self)
              normalizedState = multiChannel.normalizedPayload
            }
          } catch {
            return .failure(error)
          }

          // Update internal state for user
          if uuid == self?.configuration.uuid {
            self?.internalState.lockedWrite { state in
              normalizedState.forEach { state.findAndUpdate($0.key, state: $0.value) }
            }
          }

          return .success(normalizedState)
        })
      }
  }

  public func setPresence(
    state: [String: JSONCodable],
    on channels: [String],
    and groups: [String],
    completion: @escaping (Result<[String: [String: AnyJSON]], Error>) -> Void
  ) {
    let router = PubNubRouter(configuration: configuration,
                              endpoint: .setPresenceState(channels: channels, groups: groups, state: state))

    networkSession
      .request(with: router, requestOperator: configuration.automaticRetry)
      .validate()
      .response(decoder: SetPresenceStateResponseDecoder()) { [weak self] result in
        completion(result.map { response in
          // Get mapping of channels/groups to new state
          let normalizedState = response.payload.normalizedPayload(using: channels + groups)

          // Update state cache for channel(s) & group(s)
          self?.internalState.lockedWrite { state in
            normalizedState.forEach { state.findAndUpdate($0.key, state: $0.value) }
          }

          // Stop the subscription loop to pick up the new state
          self?.reconnect(at: self?.previousTokenResponse?.timetoken)

          // Return State that matches current user
          return normalizedState
        })
      }
  }
}
