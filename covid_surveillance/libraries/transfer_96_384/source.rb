needs 'Standard Libs/PlanParams'
needs 'Standard Libs/Debug'
needs 'Standard Libs/InstrumentHelper'
needs 'Standard Libs/ItemActions'
needs 'Standard Libs/UploadHelper'
needs 'Standard Libs/Units'
needs 'Standard Libs/CommonInputOutputNames'
needs 'Standard Libs/AssociationManagement'

needs 'Covid Surveillance/SampleConstants'
needs 'Covid Surveillance/AssociationKeys'
needs 'Covid Surveillance/CovidSurveillanceHelper'

needs 'Liquid Robot Helper/RobotHelper'

needs 'Composition Libs/Composition'
needs 'Composition Libs/CompositionHelper'

needs 'Collection Management/CollectionActions'
needs 'Collection Management/CollectionTransfer'

needs 'PCR Protocols/RunThermocycler'

needs 'Container/ItemContainer'
needs 'Container/KitHelper'
needs 'Kits/KitContents'

module Transfer_96_384

  include PlanParams
  include Debug
  include InstrumentHelper
  include ItemActions
  include UploadHelper
  include Units
  include SampleConstants
  include AssociationKeys
  include RobotHelper
  include CommonInputOutputNames
  include CompositionHelper
  include CollectionActions
  include CollectionTransfer
  include RunThermocycler
  include KitHelper
  include CovidSurveillanceHelper
  include KitContents
  include AssociationManagement

  def transfer_96_to_384(op, components, plate_name_array, plate_transfer_map, output_plate_name)
    input_plates = plate_name_array.map{ |ip| op.input(ip).collection }
    set_up_test(input_plates) if debug

    composition = CompositionFactory.build(
      component_data: components
    )
    composition.input(output_plate_name).item = op.output(output_plate_name).collection

    plate_comps = []
    plate_name_array.each do |name|
      composition.input(name).item = op.input(name).collection
      plate_comps.append(composition.input(name))
    end

    temporary_options = op.temporary[:options]

    retrieve_list = reject_components(
      list_of_rejections: [output_plate_name],
      components: composition.components
    )

    # SHOW gets the parts in the composition
    display_hash(
      title: 'Retrieve Materials',
      hash_to_show: [
        { display: 'Retrieve the Following Materials', type: 'note' },
        { display: create_location_table(retrieve_list), type: 'table' }]
    )

    display_hash(
      title: 'Get and Label Plate',
      hash_to_show: [get_and_label_new_item(composition.input(output_plate_name).item)]
    )

    program = LiquidRobotProgramFactory.build(
      program_name: temporary_options[:tr_96_384_program]
    )

    robot = LiquidRobotFactory.build(
      model: temporary_options[:tr_96_384_robot],
      name: nil,
      protocol: nil
    )
    robot_items = plate_comps + [composition.input(output_plate_name)]
    display_hash(
      title: 'Set Up and Run Robot',
      hash_to_show: use_robot(program: program,
                              robot: robot,
                              items: robot_items.map(&:display_name))
    )

    transfer_provenance(plate_transfer_map,
                        pooled_plate: output_plate_name,
                        comp: composition)
  end

  # Sets up test plates for tests runs
  def set_up_test(input_plates)
    input_plates.each do |plate|
      sample = plate.parts.first.sample
      plate.add_samples(Array.new(plate.get_empty.length, sample))
    end
  end

  # Handles the provenance for the 96 to 384 transfer
  #
  # @param plate_transfer_map
  def transfer_provenance(plate_transfer_map, pooled_plate:, comp:)
    output_plate = comp.input(pooled_plate).item
    plate_transfer_map.each do |quad|
      input_plate = comp.input(quad[:plate]).item

      row_limit = quad[:rows][1]
      column_limit = quad[:columns][1]

      input_plate.get_non_empty.each do |loc|
        target_row = loc[0] + quad[:rows][0]
        target_column = loc[1] + quad[:columns][0]
        if target_row > row_limit || target_column > column_limit
          raise 'Row or column outside of quadrant limit'
        end

        from_part = input_plate.part(loc[0], loc[1])
        output_plate.set(target_row, target_column, from_part.sample)
        to_part = output_plate.part(target_row, target_column)

        from_obj_to_obj_provenance(from_item: from_part, to_item: to_part)
      end
    end
  end

end