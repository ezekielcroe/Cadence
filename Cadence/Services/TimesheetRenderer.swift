//
//  TimesheetRenderer.swift
//  Cadence
//
//  Created by Yeo Zhi Zheng on 7/7/26.
//


//
//  TimesheetRenderer.swift
//  Cadence
//
//  Renders a TimesheetDocument to PDF. Design brief: official-looking,
//  fast for a supervisor to process. Chronological rows, not a mosaic;
//  black on white; tabular figures; activity color reduced to a thin
//  left rule; unaccounted time as labeled rows, never hidden by
//  stretching blocks. No third-party dependencies.
//

import UIKit

enum TimesheetRenderer {

    // MARK: - Layout constants (A4)

    private enum Layout {
        static let pageSize   = CGSize(width: 595.2, height: 841.8)
        static let margin: CGFloat = 48
        static var contentWidth: CGFloat { pageSize.width - margin * 2 }

        // Column x-offsets within content
        static let colStart:    CGFloat = 0
        static let colEnd:      CGFloat = 58
        static let colDuration: CGFloat = 116
        static let colActivity: CGFloat = 186
        static let colSubRight: CGFloat = contentWidth   // right-aligned figures

        static let rowHeight: CGFloat = 18
        static let remarkIndent: CGFloat = 186
    }

    private enum Fonts {
        static let title    = UIFont.systemFont(ofSize: 20, weight: .semibold)
        static let meta     = UIFont.systemFont(ofSize: 10, weight: .regular)
        static let dayHead  = UIFont.systemFont(ofSize: 12, weight: .semibold)
        static let colHead  = UIFont.systemFont(ofSize: 9,  weight: .semibold)
        static let row      = UIFont.systemFont(ofSize: 10, weight: .regular)
        static let rowNum   = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        static let remark   = UIFont.italicSystemFont(ofSize: 9)
        static let gap      = UIFont.italicSystemFont(ofSize: 10)
        static let subtotal = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
    }

    private enum Ink {
        static let primary   = UIColor.black
        static let secondary = UIColor(white: 0.35, alpha: 1)
        static let faint     = UIColor(white: 0.55, alpha: 1)
        static let rule      = UIColor(white: 0.80, alpha: 1)
        static let heavyRule = UIColor(white: 0.25, alpha: 1)
    }

    // MARK: - Public entry

    /// Renders and writes the PDF; returns the file URL for sharing.
    static func render(_ document: TimesheetDocument) throws -> URL {
        let bounds = CGRect(origin: .zero, size: Layout.pageSize)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "Cadence Timesheet \(document.periodLabel)",
            kCGPDFContextCreator as String: "Cadence"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)

        var pageNumber = 0

        let data = renderer.pdfData { ctx in
            var y = beginPage(ctx: ctx, document: document, pageNumber: &pageNumber)

            for day in document.days {
                // Day heading needs room for itself + one row; break early.
                y = ensureRoom(38, y: y, ctx: ctx, document: document, pageNumber: &pageNumber)
                y = drawDayHeading(day, at: y)

                if let intention = day.intention {
                    y = ensureRoom(14, y: y, ctx: ctx, document: document, pageNumber: &pageNumber)
                    y = drawAnnotation("Intention: \(intention)", at: y)
                }

                for row in day.rows {
                    let needed = Layout.rowHeight + CGFloat(row.remarks.count) * 12
                    y = ensureRoom(needed, y: y, ctx: ctx, document: document, pageNumber: &pageNumber)
                    y = drawRow(row, at: y)
                }

                if let reflection = day.reflection {
                    y = ensureRoom(14, y: y, ctx: ctx, document: document, pageNumber: &pageNumber)
                    y = drawAnnotation("Reflection: \(reflection)", at: y)
                }

                y = ensureRoom(20, y: y, ctx: ctx, document: document, pageNumber: &pageNumber)
                y = drawDaySubtotal(day, includeGaps: document.includeGaps, at: y)
                y += 8
            }

            y = ensureRoom(summaryHeight(for: document), y: y, ctx: ctx,
                           document: document, pageNumber: &pageNumber)
            _ = drawSummary(document, at: y)
        }

        let filename = "Cadence-Timesheet-\(fileDateStamp(document.periodStart))-\(fileDateStamp(document.periodEnd)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Page management

    private static func beginPage(
        ctx: UIGraphicsPDFRendererContext,
        document: TimesheetDocument,
        pageNumber: inout Int
    ) -> CGFloat {
        ctx.beginPage()
        pageNumber += 1
        var y = Layout.margin

        if pageNumber == 1 {
            y = drawDocumentHeader(document, at: y)
        }

        y = drawColumnHeader(at: y)
        drawPageFooter(pageNumber: pageNumber, document: document)
        return y
    }

    private static func ensureRoom(
        _ needed: CGFloat,
        y: CGFloat,
        ctx: UIGraphicsPDFRendererContext,
        document: TimesheetDocument,
        pageNumber: inout Int
    ) -> CGFloat {
        let footerReserve: CGFloat = 36
        if y + needed > Layout.pageSize.height - Layout.margin - footerReserve {
            return beginPage(ctx: ctx, document: document, pageNumber: &pageNumber)
        }
        return y
    }

    // MARK: - Sections

    private static func drawDocumentHeader(_ doc: TimesheetDocument, at y: CGFloat) -> CGFloat {
        var y = y
        draw("Timesheet", font: Fonts.title, color: Ink.primary, x: 0, y: y)
        y += 28

        if !doc.ownerName.isEmpty {
            draw("Name: \(doc.ownerName)", font: Fonts.meta, color: Ink.secondary, x: 0, y: y)
            y += 13
        }
        draw("Period: \(doc.periodLabel)", font: Fonts.meta, color: Ink.secondary, x: 0, y: y)
        draw("Generated: \(DurationFormat.dayHeading.string(from: doc.generatedAt))",
             font: Fonts.meta, color: Ink.secondary,
             x: 0, y: y, width: Layout.contentWidth, alignment: .right)
        y += 13
        draw("Accountable hours: \(doc.windowDescription)", font: Fonts.meta, color: Ink.secondary, x: 0, y: y)
        y += 16

        strokeRule(y: y, color: Ink.heavyRule, width: 1)
        return y + 10
    }

    private static func drawColumnHeader(at y: CGFloat) -> CGFloat {
        let c = Ink.faint
        draw("START",    font: Fonts.colHead, color: c, x: Layout.colStart,    y: y)
        draw("END",      font: Fonts.colHead, color: c, x: Layout.colEnd,      y: y)
        draw("DURATION", font: Fonts.colHead, color: c, x: Layout.colDuration, y: y)
        draw("ACTIVITY", font: Fonts.colHead, color: c, x: Layout.colActivity, y: y)
        let nextY = y + 13
        strokeRule(y: nextY, color: Ink.rule, width: 0.5)
        return nextY + 5
    }

    private static func drawDayHeading(_ day: TimesheetDay, at y: CGFloat) -> CGFloat {
        let y = y + 6
        draw(DurationFormat.dayHeading.string(from: day.date),
             font: Fonts.dayHead, color: Ink.primary, x: 0, y: y)
        return y + 18
    }

    private static func drawRow(_ row: TimesheetRow, at y: CGFloat) -> CGFloat {
        var y = y
        let isGap = row.kind == .gap
        let numColor: UIColor = isGap ? Ink.faint : Ink.primary

        // Thin activity-color rule at the left of block rows.
        if !isGap, let hex = row.activityColor {
            let ctx = UIGraphicsGetCurrentContext()
            ctx?.setFillColor(UIColor(hexString: hex).cgColor)
            ctx?.fill(CGRect(x: Layout.margin - 8, y: y + 1, width: 2.5, height: 12))
        }

        draw(DurationFormat.time.string(from: row.start), font: Fonts.rowNum, color: numColor, x: Layout.colStart, y: y)
        draw(DurationFormat.time.string(from: row.end),   font: Fonts.rowNum, color: numColor, x: Layout.colEnd,   y: y)
        draw(DurationFormat.hoursMinutes(isGap ? row.duration : row.netDuration),
             font: Fonts.rowNum, color: numColor, x: Layout.colDuration, y: y)

        var label = row.activityName
        if row.breakDuration >= 60 {
            label += "  (incl. \(DurationFormat.hoursMinutes(row.breakDuration)) breaks × \(row.breakCount))"
        }
        draw(label,
             font: isGap ? Fonts.gap : Fonts.row,
             color: isGap ? Ink.faint : Ink.primary,
             x: Layout.colActivity, y: y,
             width: Layout.contentWidth - Layout.colActivity)
        y += Layout.rowHeight

        for remark in row.remarks {
            draw("— \(remark)", font: Fonts.remark, color: Ink.secondary,
                 x: Layout.remarkIndent, y: y - 3,
                 width: Layout.contentWidth - Layout.remarkIndent)
            y += 12
        }
        return y
    }

    private static func drawAnnotation(_ text: String, at y: CGFloat) -> CGFloat {
        draw(text, font: Fonts.remark, color: Ink.secondary, x: 0, y: y, width: Layout.contentWidth)
        return y + 14
    }

    private static func drawDaySubtotal(_ day: TimesheetDay, includeGaps: Bool, at y: CGFloat) -> CGFloat {
        strokeRule(y: y, color: Ink.rule, width: 0.5)
        let y2 = y + 4
        var text = "Day total: \(DurationFormat.hoursMinutes(day.trackedSubtotal))"
        if includeGaps && day.unaccountedSubtotal >= 60 {
            text += "   ·   Unaccounted: \(DurationFormat.hoursMinutes(day.unaccountedSubtotal))"
        }
        draw(text, font: Fonts.subtotal, color: Ink.primary,
             x: 0, y: y2, width: Layout.contentWidth, alignment: .right)
        return y2 + 16
    }

    private static func summaryHeight(for doc: TimesheetDocument) -> CGFloat {
        60 + CGFloat(doc.activityTotals.count) * 15 + 70
    }

    private static func drawSummary(_ doc: TimesheetDocument, at y: CGFloat) -> CGFloat {
        var y = y + 8
        strokeRule(y: y, color: Ink.heavyRule, width: 1)
        y += 10

        draw("Period Summary", font: Fonts.dayHead, color: Ink.primary, x: 0, y: y)
        y += 20

        for (name, duration) in doc.activityTotals {
            draw(name, font: Fonts.row, color: Ink.primary, x: 0, y: y)
            draw(DurationFormat.hoursMinutes(duration), font: Fonts.rowNum, color: Ink.primary,
                 x: 0, y: y, width: 260, alignment: .right)
            y += 15
        }

        y += 6
        strokeRule(y: y, color: Ink.rule, width: 0.5, width2: 260)
        y += 5
        draw("Total tracked", font: Fonts.subtotal, color: Ink.primary, x: 0, y: y)
        draw(DurationFormat.hoursMinutes(doc.totalTracked), font: Fonts.subtotal, color: Ink.primary,
             x: 0, y: y, width: 260, alignment: .right)
        y += 15

        if doc.includeGaps && doc.totalUnaccounted >= 60 {
            draw("Total unaccounted", font: Fonts.row, color: Ink.secondary, x: 0, y: y)
            draw(DurationFormat.hoursMinutes(doc.totalUnaccounted), font: Fonts.rowNum, color: Ink.secondary,
                 x: 0, y: y, width: 260, alignment: .right)
            y += 15
        }

        y += 30
        draw("Signature: ______________________________          Date: ______________",
             font: Fonts.meta, color: Ink.secondary, x: 0, y: y)
        return y + 14
    }

    private static func drawPageFooter(pageNumber: Int, document: TimesheetDocument) {
        let y = Layout.pageSize.height - Layout.margin + 14
        draw("Cadence · \(document.periodLabel)", font: Fonts.meta, color: Ink.faint,
             x: 0, y: y)
        draw("Page \(pageNumber)", font: Fonts.meta, color: Ink.faint,
             x: 0, y: y, width: Layout.contentWidth, alignment: .right)
    }

    // MARK: - Drawing primitives

    private static func draw(
        _ text: String,
        font: UIFont,
        color: UIColor,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat = 400,
        alignment: NSTextAlignment = .left
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(
            in: CGRect(x: Layout.margin + x, y: y, width: width, height: font.lineHeight + 4),
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: style
            ]
        )
    }

    private static func strokeRule(y: CGFloat, color: UIColor, width: CGFloat, width2: CGFloat? = nil) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.move(to: CGPoint(x: Layout.margin, y: y))
        ctx.addLine(to: CGPoint(x: Layout.margin + (width2 ?? Layout.contentWidth), y: y))
        ctx.strokePath()
    }

    private static func fileDateStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f.string(from: date)
    }
}

// MARK: - UIColor hex helper (UIKit-side; the app's Color(hex:) is SwiftUI)

private extension UIColor {
    convenience init(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            red:   CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8)  & 0xFF) / 255,
            blue:  CGFloat(value         & 0xFF) / 255,
            alpha: 1
        )
    }
}