import Foundation

struct ForegroundReconcilePermit: Sendable {
    private let authority: ForegroundReconcilePermitAuthority
    private let epoch: UInt64

    fileprivate init(
        authority: ForegroundReconcilePermitAuthority,
        epoch: UInt64
    ) {
        self.authority = authority
        self.epoch = epoch
    }

    func isValidAtWorkerIngress() -> Bool {
        authority.isValid(epoch: epoch)
    }
}

struct BackgroundReconcilePermit: Sendable {
    private let authority: ForegroundReconcilePermitAuthority
    private let epoch: UInt64

    fileprivate init(
        authority: ForegroundReconcilePermitAuthority,
        epoch: UInt64
    ) {
        self.authority = authority
        self.epoch = epoch
    }

    func isValidAtWorkerIngress() -> Bool {
        authority.isValidBackground(epoch: epoch)
    }
}

final class ForegroundReconcilePermitAuthority: @unchecked Sendable {
    // The lock orders lifecycle invalidation against the worker's final permit check.
    private let lock = NSLock()
    private var epoch: UInt64 = 0
    private var activeForegroundEpoch: UInt64?
    private var activeBackgroundEpoch: UInt64?

    func beginForegroundEpoch() -> ForegroundReconcilePermit {
        lock.withLock {
            epoch &+= 1
            activeForegroundEpoch = epoch
            activeBackgroundEpoch = nil
            return ForegroundReconcilePermit(authority: self, epoch: epoch)
        }
    }

    func currentPermit() -> ForegroundReconcilePermit? {
        lock.withLock {
            guard let activeForegroundEpoch else { return nil }
            return ForegroundReconcilePermit(
                authority: self,
                epoch: activeForegroundEpoch
            )
        }
    }

    func beginBackgroundEpoch() -> BackgroundReconcilePermit {
        lock.withLock {
            epoch &+= 1
            activeForegroundEpoch = nil
            activeBackgroundEpoch = epoch
            return BackgroundReconcilePermit(authority: self, epoch: epoch)
        }
    }

    fileprivate func isValid(epoch: UInt64) -> Bool {
        lock.withLock {
            activeForegroundEpoch == epoch && self.epoch == epoch
        }
    }

    fileprivate func isValidBackground(epoch: UInt64) -> Bool {
        lock.withLock {
            activeBackgroundEpoch == epoch && self.epoch == epoch
        }
    }
}
