//
//  ArisFetch.swift
//  aris-tools
//
//  One GET with a ceiling on the reply, for the lookups that read a small JSON answer from a service outside the Mac
//  (`stock` and `currency`: Yahoo's chart and search). The body is taken in as it arrives and the request is dropped
//  the moment it says it is, or grows, longer than the ceiling: a reply that long is no data, and the command then
//  says its plain line. Nothing but a 200 is read at all. Foundation only (tested with a made-up reply, no network).
//

import Foundation

enum ArisCappedFetch {
    enum Reply: Equatable {
        case ok(Data)
        /// The service answered with anything but a 200.
        case refused
        /// No answer in time, or no connection.
        case unreachable
        /// A 200 longer than the ceiling: dropped unread.
        case tooLong
    }

    /// `request`'s reply, at most `most` bytes of it. `wait`: how long the whole exchange may take.
    static func get(_ request: URLRequest, most: Int, wait: TimeInterval = 10, configuration: URLSessionConfiguration = .default) -> Reply {
        let receiver = Receiver(most: most)
        let session = URLSession(configuration: configuration, delegate: receiver, delegateQueue: nil)
        let task = session.dataTask(with: request)
        task.resume()
        guard receiver.done.wait(timeout: .now() + wait) == .success else {
            session.invalidateAndCancel()
            return .unreachable
        }
        session.finishTasksAndInvalidate()
        return receiver.reply
    }

    /// Takes the reply in piece by piece; `reply` is read only after `done`.
    private final class Receiver: NSObject, URLSessionDataDelegate {
        let most: Int
        let done = DispatchSemaphore(value: 0)
        private(set) var reply = Reply.unreachable
        private var body = Data()
        /// The answer is settled (refused, or too long): what still arrives is nothing.
        private var settled = false

        init(most: Int) { self.most = most }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return settle(.refused, completionHandler) }
            // A length said up front is believed when it is over the ceiling; a short or missing one is counted below.
            if response.expectedContentLength > Int64(most) { return settle(.tooLong, completionHandler) }
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            guard !settled else { return }
            guard body.count + data.count <= most else {
                settled = true
                reply = .tooLong
                body = Data()
                return dataTask.cancel()
            }
            body.append(data)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if !settled, error == nil { reply = .ok(body) }
            done.signal()
        }

        private func settle(_ answer: Reply, _ completionHandler: (URLSession.ResponseDisposition) -> Void) {
            settled = true
            reply = answer
            completionHandler(.cancel)
        }
    }
}
