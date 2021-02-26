# typed: false
# frozen_string_literal: true

# This is a default, one-size-fits all protocol that shows how you can
# access the inputs and outputs of the operations associated with a job.
needs 'Barcodes/BarcodeHelper'
needs 'Barcodes/BarcodeKeys'
needs 'Covid Surveillance/SampleConstants'
needs 'Covid Surveillance/AssociationKeys'

class Protocol

  include BarcodeHelper
  include BarcodeKeys

  include SampleConstants
  include AssociationKeys

  SPECIMEN_PREFIX = 'Surveillance Specimen'
  SPECIMEN_DESCRIPTION = 'A surveillance sample processed at the Genome Core'

  def main
    operations.each do |op|
      show do
        title 'This protocol is not finished yet'
        note 'Will create many items or object type. to test other parts of workflow'
      end
      project = op.input(PROJECT).to_s
      object_type = op.input(OBJECT_TYPE).to_s
      sample_type = op.input(SAMPLE_TYPE).to_s

      barcode_ids = show_scan_new_items

      barcode_ids.each do |barcode|
        sample = Sample.creator(
          {
            sample_type_id: SampleType.find_by_name(sample_type).id,
            description: SPECIMEN_DESCRIPTION,
            name: "#{SPECIMEN_PREFIX} #{barcode}",
            project: project,
            field_values: [
              { name: 'Barcode ID', value: barcode }
            ]
          }, User.find(1)
        )

        sample.make_item(object_type)
      end
    end
    {}
  end
end
