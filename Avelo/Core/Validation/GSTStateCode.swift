import Foundation

/// The standard CBIC GST state-code table: the first two digits of any
/// Indian GSTIN identify the issuing state/UT (e.g. `27ABCDE1234F1Z5` was
/// issued in Maharashtra, code `27`). Used to derive an invoice's place of
/// supply (AVL-P0-022) without needing a separate address/state field on
/// `Account` -- a registered party's GSTIN already carries this.
///
/// This is static reference data (the code list is fixed by statute), not a
/// database table.
public enum GSTStateCode {
    public static let table: [String: String] = [
        "01": "Jammu and Kashmir",
        "02": "Himachal Pradesh",
        "03": "Punjab",
        "04": "Chandigarh",
        "05": "Uttarakhand",
        "06": "Haryana",
        "07": "Delhi",
        "08": "Rajasthan",
        "09": "Uttar Pradesh",
        "10": "Bihar",
        "11": "Sikkim",
        "12": "Arunachal Pradesh",
        "13": "Nagaland",
        "14": "Manipur",
        "15": "Mizoram",
        "16": "Tripura",
        "17": "Meghalaya",
        "18": "Assam",
        "19": "West Bengal",
        "20": "Jharkhand",
        "21": "Odisha",
        "22": "Chhattisgarh",
        "23": "Madhya Pradesh",
        "24": "Gujarat",
        "25": "Daman and Diu",
        "26": "Dadra and Nagar Haveli",
        "27": "Maharashtra",
        "28": "Andhra Pradesh (Old)",
        "29": "Karnataka",
        "30": "Goa",
        "31": "Lakshadweep",
        "32": "Kerala",
        "33": "Tamil Nadu",
        "34": "Puducherry",
        "35": "Andaman and Nicobar Islands",
        "36": "Telangana",
        "37": "Andhra Pradesh",
        "38": "Ladakh",
        "97": "Other Territory",
        "99": "Centre Jurisdiction"
    ]

    /// The state/UT name for a GSTIN's leading two-digit code, or `nil` if
    /// the string is too short or the prefix isn't a recognized code.
    public static func stateName(forGSTIN gstin: String) -> String? {
        guard gstin.count >= 2 else { return nil }
        return table[String(gstin.prefix(2))]
    }

    /// The two-digit state code itself (not the name) for a GSTIN, or `nil`
    /// if the prefix isn't a recognized code. Used to compare place-of-supply
    /// between two parties without caring what the state is actually called.
    public static func code(forGSTIN gstin: String) -> String? {
        guard gstin.count >= 2 else { return nil }
        let prefix = String(gstin.prefix(2))
        return table[prefix] != nil ? prefix : nil
    }
}
