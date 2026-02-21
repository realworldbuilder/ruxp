import SwiftUI

// MARK: - Workout Canvas Component Protocol

protocol WorkoutCanvasComponent: View {
    var componentID: UUID { get }
    var priority: ComponentPriority { get }
}

enum ComponentPriority: Int, Comparable {
    case ambient = 0    // background, subtle
    case suggested = 1  // AI suggestions
    case planned = 2    // trainer-planned
    case active = 3     // currently relevant
    case urgent = 4     // PR alert, rest timer, etc.
    
    static func < (lhs: ComponentPriority, rhs: ComponentPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Tag Model

struct ExerciseTag: Identifiable, Equatable {
    let id = UUID()
    let name: String
    var source: TagSource
    var isCompleted: Bool = false
    
    enum TagSource {
        case planned    // From trainer chat workout plan
        case suggested  // From suggestion engine
        case history    // From workout history patterns
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var alignment: HorizontalAlignment = .center
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            guard index < subviews.count else { break }
            let adjustedX: CGFloat
            switch alignment {
            case .center:
                // Center each row
                let rowWidth = result.rowWidths[result.rowForIndex[index] ?? 0] ?? 0
                let offset = (bounds.width - rowWidth) / 2
                adjustedX = bounds.minX + position.x + offset
            default:
                adjustedX = bounds.minX + position.x
            }
            subviews[index].place(at: CGPoint(x: adjustedX, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private struct ArrangementResult {
        var size: CGSize
        var positions: [CGPoint]
        var rowWidths: [Int: CGFloat]
        var rowForIndex: [Int: Int]
    }
    
    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> ArrangementResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var rowWidths: [Int: CGFloat] = [:]
        var rowForIndex: [Int: Int] = [:]
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var currentRow = 0
        
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && currentX > 0 {
                rowWidths[currentRow] = currentX - spacing
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
                currentRow += 1
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            rowForIndex[index] = currentRow
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        
        rowWidths[currentRow] = currentX - spacing
        
        return ArrangementResult(
            size: CGSize(width: maxWidth, height: currentY + rowHeight),
            positions: positions,
            rowWidths: rowWidths,
            rowForIndex: rowForIndex
        )
    }
}

// MARK: - Exercise Tag Cloud View

struct ExerciseTagCloud: View, WorkoutCanvasComponent {
    let tags: [ExerciseTag]
    var reason: String = ""
    @Binding var selectedTag: String?
    @State private var animationPhase: CGFloat = 0
    
    // MARK: - WorkoutCanvasComponent
    let componentID = UUID()
    
    var priority: ComponentPriority {
        // Determine priority based on tag contents
        if tags.contains(where: { $0.source == .planned }) {
            return .planned
        } else if tags.contains(where: { $0.source == .suggested }) {
            return .suggested
        } else {
            return .ambient
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            if !reason.isEmpty {
                Text(reason)
                    .font(.caption2)
                    .foregroundColor(Theme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(1.2)
            }
            
            FlowLayout(spacing: 12, alignment: .center) {
                ForEach(Array(tags.enumerated()), id: \.element.id) { index, tag in
                    TagChip(
                        tag: tag,
                        isSelected: selectedTag == tag.name,
                        isDimmed: selectedTag != nil && selectedTag != tag.name
                    ) {
                        handleTagTap(tag.name)
                    }
                    .offset(y: floatOffset(for: index))
                    .animation(
                        .easeInOut(duration: Double.random(in: 2.5...4.0))
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.15),
                        value: animationPhase
                    )
                }
            }
            
            // Show selected exercise name prominently
            if let selected = selectedTag {
                VStack(spacing: 8) {
                    Text("CURRENT EXERCISE")
                        .font(.caption2)
                        .foregroundColor(Theme.textTertiary)
                        .textCase(.uppercase)
                        .tracking(1.2)
                    
                    Text(selected)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(Theme.accent)
                        .transition(.scale.combined(with: .opacity))
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .onAppear {
            animationPhase = 1
        }
    }
    
    private func handleTagTap(_ tagName: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if selectedTag == tagName {
                selectedTag = nil // Deselect if already selected
            } else {
                selectedTag = tagName // Select new tag
            }
        }
        
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    private func floatOffset(for index: Int) -> CGFloat {
        let base: CGFloat = animationPhase == 0 ? 0 : CGFloat.random(in: -2...2)
        return base
    }
}

// MARK: - Individual Tag Chip

struct TagChip: View {
    let tag: ExerciseTag
    let isSelected: Bool
    let isDimmed: Bool
    let onTap: () -> Void
    @State private var isPressed = false
    @State private var pulsePhase: CGFloat = 0
    
    private var chipStyle: (bg: Color, fg: Color, border: Color, opacity: Double, scale: CGFloat) {
        let baseOpacity: Double = isDimmed ? 0.4 : 1.0
        let scale: CGFloat = isSelected ? 1.08 : (isPressed ? 0.96 : 1.0)
        
        if tag.isCompleted {
            return (Theme.surface, Theme.textTertiary, Theme.textTertiary, 0.5 * baseOpacity, scale)
        }
        
        if isSelected {
            // Selected state - glowing accent
            return (Theme.accent, .white, Theme.accent, baseOpacity, scale)
        }
        
        switch tag.source {
        case .planned:
            return (Theme.accent, .white, Theme.accent, baseOpacity, scale)
        case .suggested:
            return (Theme.accentSubtle, Theme.accent, Theme.accent.opacity(0.3), baseOpacity, scale)
        case .history:
            return (Color.white.opacity(0.08), Theme.textSecondary, Color.white.opacity(0.15), 0.85 * baseOpacity, scale)
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if tag.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
                if tag.source == .planned && !tag.isCompleted {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                }
                Text(tag.name)
                    .font(.system(size: 14, weight: tag.source == .planned ? .semibold : .medium))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(chipStyle.fg)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(chipStyle.bg, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? Theme.accent : chipStyle.border,
                        lineWidth: isSelected ? 2.0 : (tag.source == .planned ? 1.5 : 0.5)
                    )
                    .opacity(isSelected ? pulsePhase : 1.0)
            )
            .opacity(chipStyle.opacity)
            .scaleEffect(chipStyle.scale)
            .if(isSelected) { view in
                view.shadow(color: Theme.accent.opacity(0.4), radius: 8, y: 3)
            }
            .if(tag.source == .planned && !tag.isCompleted && !isSelected) { view in
                view.shadow(color: Theme.accent.opacity(0.2), radius: 4, y: 2)
            }
            .strikethrough(tag.isCompleted, color: chipStyle.fg)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
        .onAppear {
            if isSelected {
                startPulseAnimation()
            }
        }
        .onChange(of: isSelected) { _, selected in
            if selected {
                startPulseAnimation()
            } else {
                pulsePhase = 0
            }
        }
    }
    
    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulsePhase = 0.3
        }
    }
}

// MARK: - View Extension for conditional modifiers

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}