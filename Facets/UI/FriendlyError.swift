import Foundation
import MeshKit

/// An error put the way a person would say it: what happened, and what to do about
/// it. System error strings ("The file couldn't be opened because there is no such
/// file") never reach the screen on their own.
struct FriendlyError: Equatable {
    enum Kind: Equatable {
        case missing, noAccess, notDownloaded, notAModel, empty, damaged, noShapes, noSpace, other
    }

    let kind: Kind
    let title: String
    let message: String

    /// For a file that couldn't be opened or read.
    init(opening error: Error) {
        if let model = error as? ModelError {
            switch model {
            case .unsupportedFormat:
                self.init(.notAModel, "Not an STL or 3MF File", "Facets opens STL and 3MF files. This one is something else, or has the wrong extension.")
            case .emptyFile:
                self.init(.empty, "This File Is Empty", "It has no data in it. If it came from a download, try downloading it again.")
            case .noGeometry:
                self.init(.noShapes, "Nothing to Show", "The file opened, but it has no shapes in it.")
            case .corrupt:
                self.init(.damaged, "Can't Read This File", "It may be damaged or only partly downloaded, or use a part of the format Facets doesn't read yet. Try downloading it again, or open it in your slicer.")
            }
            return
        }
        self.init(file: error)
    }

    /// For file operations: import, rename, move, delete.
    init(file error: Error) {
        let ns = error as NSError
        switch (ns.domain, ns.code) {
        case (NSCocoaErrorDomain, NSFileNoSuchFileError), (NSCocoaErrorDomain, NSFileReadNoSuchFileError), (NSPOSIXErrorDomain, Int(ENOENT)):
            self.init(.missing, "File Not Found", "It was moved, renamed or deleted since Facets last saw it.")
        case (NSCocoaErrorDomain, NSFileReadNoPermissionError), (NSCocoaErrorDomain, NSFileWriteNoPermissionError), (NSPOSIXErrorDomain, Int(EPERM)), (NSPOSIXErrorDomain, Int(EACCES)):
            self.init(.noAccess, "No Access to This File", "Facets can only open files you choose. Open it again from Files, or add its folder under Library › Browse.")
        case (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError), (NSPOSIXErrorDomain, Int(ENOSPC)):
            self.init(.noSpace, "Not Enough Storage", "Free up some space on this device and try again.")
        case (NSCocoaErrorDomain, NSUbiquitousFileUnavailableError):
            self.init(.notDownloaded, "Couldn't Download From iCloud", "Check your connection, then try again.")
        default:
            self.init(.other, "Something Went Wrong", "Facets couldn't finish that. Try again in a moment.")
        }
    }

    private init(_ kind: Kind, _ title: String, _ message: String) {
        self.kind = kind
        self.title = title
        self.message = message
    }
}
