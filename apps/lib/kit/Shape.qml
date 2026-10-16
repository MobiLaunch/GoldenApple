// A rectangle, rounded rectangle, circle or capsule, filled with a colour,
// gradient, material or image (the box's background).
import QtQuick

Box {
    id: root
    property string shape: "roundedRectangle"  // rectangle | roundedRectangle | circle | capsule
    contentWidth: 80
    contentHeight: 80
    background: ({ type: "color", color: "accent" })
    cornerRadius: shape === "circle" || shape === "capsule" ? Math.min(box.width, box.height) / 2 : shape === "rectangle" ? 0 : 14
}
