//
//  NetworkServices.swift
//  Coinless
//
//  Created by Luthfi Asmara on 17/02/24.
//

import Foundation
import Alamofire
import Moya
import ObjectMapper
import RxSwift
import SystemConfiguration.CaptiveNetwork

class NetworkService {
  static let shared = NetworkService()

  private var queue = [() -> Void]()
  private var isRun = false

  func connect<T: Mappable>(api: CoinlessAPI, mappableType: T.Type) -> Observable<T> {
    let subject = ReplaySubject<T>.createUnbounded()
    let observe = subject.do(
      onError: { [weak self] error in
        if case let ApiError.middlewareError(code, _) = error, code == 401 {
          self?.stop()
        } else {
          self?.next()
        }
      },
      onCompleted: { [weak self] in
        self?.next()
      }
    )

    exec { [weak self] in self?.createRequest(api, mappableType, subject) }

    return observe
  }

  private func exec(entry: @escaping () -> Void) {
    queue.append(entry)
    if isRun == false {
      queue.first?()
      isRun = true
    }
  }

  private func next() {
    queue.removeFirst()
    isRun = (queue.first != nil)
    queue.first?()
  }

  private func stop() {
    queue.removeAll()
    isRun = false
  }

  private func createRequest<T: Mappable>(
    _ apiCall: CoinlessAPI,
    _ outType: T.Type,
    _ subject: ReplaySubject<T>,
    _ payload: Any? = nil
  ) {
    let provider = MoyaProvider<CoinlessAPI>(endpointClosure: apiCall.endpointClosure)

    provider.request(apiCall) { result in
      switch result {
      case .success(let response):
        do {
          guard let json = try response.mapJSON() as? [String: Any]
          else { throw ApiError.invalidJSONError }

          print("[NETWORK][\(response.statusCode)] \(apiCall.path)")

          switch response.statusCode {
          case 200:

            guard let data = outType.init(map: Map(mappingType: .fromJSON, JSON: json))
            else { throw ApiError.failedMappingError }

            subject.onNext(data)
            subject.onCompleted()

          case 404:
            print("NOT FOUND")

          default:
            print("Unknown statusCode: \(response.statusCode)")
          }
        } catch {
          subject.onError(error)
        }

      case .failure:
        subject.onError(ApiError.connectionError)
      }
    }
  }
}
