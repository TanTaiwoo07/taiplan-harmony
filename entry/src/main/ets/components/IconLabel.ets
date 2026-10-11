@Builder
export function IconLabel(label: string, icon: Resource, color: ResourceColor = $r('app.color.text_primary'), size: number = 14) {
  Row({ space: 8 }) {
    Image(icon).width(20).height(20).accessibilityLevel('no')
    Text(label).fontSize(size).fontColor(color).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
  }.justifyContent(FlexAlign.Center)
}
