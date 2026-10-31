// A row of a form: a label on the left, its control on the right.
//   FormSection { FormRow { title: "Show battery percentage"; Switch { … } } }
// The control is named by the row's title for screen readers, unless it has
// a name of its own.
import QtQuick

ListRow {
    id: row
    Component.onCompleted: {
        for (const control of trailingItem.children)
            if (!control.Accessible.name) control.Accessible.name = Qt.binding(() => row.title)
    }
}
