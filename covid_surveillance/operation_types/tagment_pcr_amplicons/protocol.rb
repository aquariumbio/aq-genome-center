# typed: false
# frozen_string_literal: true

needs 'Standard Libs/PlanParams'
needs 'Standard Libs/Debug'
needs 'Standard Libs/InstrumentHelper'
needs 'Standard Libs/ItemActions'
needs 'Standard Libs/UploadHelper'
needs 'Small Instruments/Centrifuges'
needs 'Small Instruments/Shakers'
needs 'Standard Libs/Units'
needs 'Covid Surveillance/SampleConstants'
needs 'Covid Surveillance/AssociationKeys'
needs 'Liquid Robot Helper/RobotHelper'

needs 'CompositionLibs/AbstractComposition'
needs 'CompositionLibs/CompositionHelper'

needs 'Collection Management/CollectionTransfer'
needs 'Collection Management/CollectionActions'

needs 'PCR Protocols/RunThermocycler'


class Protocol
  include PlanParams
  include Debug
  include InstrumentHelper
  include ItemActions
  include UploadHelper
  include Centrifuges
  include Shakers
  include Units
  include SampleConstants
  include AssociationKeys
  include RobotHelper
  include CompositionHelper
  include CollectionTransfer
  include CollectionActions
  include RunThermocycler

  COV1 = 'COV1'.freeze
  COV2 = 'COV2'.freeze
#========== Composition Definitions ==========#

  AREA_SEAL = "Microseal 'B' adhesive seals"
  TAGMENT_KIT = 'Tagment PCR Amplicons Kit'

  EBLTS_HT = 'Enrichment BLT HT'
  TB1_HT = 'Tagmentation Buffer 1 HT'
  WATER = 'Nuclease-free water'

  MICRO_TUBES = '1.7 ml Tube'
  TEST_TUBE = '15 ml Reagent Tube'

  def components
    [
       {
         input_name: COV1,
         qty: 10, units: MICROLITERS,
         sample_name: 'Pooled Specimens',
         object_type: '96-Well Plate'
       },
       {
        input_name: COV2,
        qty: 10, units: MICROLITERS,
        sample_name: 'Pooled Specimens',
        object_type: '96-Well Plate'
      },
      {
        input_name: MASTER_MIX,
        qty: 30, units: MICROLITERS,
        sample_name: MASTER_MIX,
        object_type: TEST_TUBE
      },
      {
        input_name: WATER,
        qty: 20, units: MICROLITERS,
        sample_name: WATER,
        object_type: 'Reagent Bottle'
      }
    ]
  end

  def consumables
    [
      {
        input_name: AREA_SEAL,
        qty: 1, units: 'Each',
        description: 'Adhesive Plate Seal'
      },
      {
        input_name: TEST_TUBE,
        qty: 1, units: 'Each',
        description: TEST_TUBE
      }
    ]
  end

  def kits
    [
      {
        input_name: TAGMENT_KIT,
        qty: 1, units: 'kits',
        description: 'Kit Tagment PCR Aplicons',
        location: 'M80 Freezer',
        components: [
          {
            input_name: EBLTS_HT,
            qty:  4, units: MICROLITERS,
            sample_name: EBLTS_HT,
            object_type: 'Reagent Bottle'
          },
          {
            input_name: TB1_HT,
            qty: 12, units: MICROLITERS,
            sample_name: TB1_HT,
            object_type: 'Reagent Bottle'
          }
        ],
        consumables: [
          {
            input_name: MICRO_TUBES,
            qty: 1, units: 'Each',
            description: '1.7 ml Tube'
          }
        ]
      }
    ]
  end

########## DEFAULT PARAMS ##########

# Default parameters that are applied equally to all operations.
#   Can be overridden by:
#   * Associating a JSON-formatted list of key, value pairs to the `Plan`.
#   * Adding a JSON-formatted list of key, value pairs to an `Operation`
#     input of type JSON and named `Options`.
#
def default_job_params
  {
  }
end

# Default parameters that are applied to individual operations.
#   Can be overridden by:
#   * Adding a JSON-formatted list of key, value pairs to an `Operation`
#     input of type JSON and named `Options`.
#
def default_operation_params
  {
    robot_program: 'abstract program',
    instrument_model: TestLiquidHandlingRobot::MODEL,
    storage_location: 'M80',
    shaker_parameters: { time: create_qty(qty: 1, units: MINUTES),
                        speed: create_qty(qty: 1600, units: RPM) },
    centrifuge_parameters: { time: create_qty(qty: 1, units: MINUTES),
                            speed: create_qty(qty: 1000, units: TIMES_G) },
    thermocycler_model: TestThermocycler::MODEL,
    program_name: 'CDC_TaqPath_CG',
    qpcr: true
  }
end

########## MAIN ##########

def main
  @job_params = update_all_params(
    operations: operations,
    default_job_params: default_job_params,
    default_operation_params: default_operation_params
  )

  paired_ops = pair_ops_with_instruments(operations: operations,
                                         instrument_key: LIQUID_ROBOT_PARAM)

  remove_unpaired_operations(operations - paired_ops)

  paired_ops.make

  paired_ops.each do |op|
    set_up_test(op) if debug
    date = DateTime.now.strftime('%Y-%m-%d')
    file_name = "#{date}_Op_#{op.id}_Plate_#{op.output(POOLED_PLATE).collection.id}"

    composition = CompositionFactory.build(components: components,
                                           consumables: consumables,
                                           kits: kits)

    temporary_options = op.temporary[:options]

    program = LiquidRobotProgramFactory.build(
      program_name: temporary_options[:robot_program]
    )

    robot = LiquidRobotFactory.build(model: temporary_options[:instrument_model],
                                     name: op.temporary[INSTRUMENT_NAME],
                                     protocol: self)

    # check compatability for all three plates??
    unless check_robot_compatibility(input_object: op.output(POOLED_PLATE).collection,
                                     robot: robot,
                                     program: program)
      remove_unpaired_operations([op])
      next
    end

    composition.input(COV1).item = op.input(COV1).collection
    composition.input(COV2).item = op.input(COV2).collection
    input_plate1 = composition.input(COV1).item
    input_plate2 = composition.input(COV2).item
    output_plate = op.output(POOLED_PLATE).collection

    composition.make_kit_component_items

    mm = composition.input(MASTER_MIX)
    adj_multi = input_plate1.get_non_empty.length
    mm_components = [composition.input(TAGMENT_KIT).input(EBLTS_HT),
                     composition.input(TAGMENT_KIT).input(TB1_HT),
                     composition.input(WATER)]

    composition.input(WATER).item = make_item(sample: composition.input(WATER).sample,
                                              object_type: composition.input(WATER).object_type)

    show_retrieve_components([composition.input(COV1), composition.input(COV2), composition.input(WATER)])
    show_retrieve_consumables(composition.consumables)
    show_retrieve_kits(composition.kits)

    mm.item = make_item(sample: mm.sample,
                        object_type: mm.object_type)

    frozen = check_if_frozen([input_plate1, input_plate2])

    vortex_objs(composition.kits.map { |kit|
      kit.composition.components.map(&:input_name)
    }.flatten)

    retrieve_materials([input_plate1, input_plate2])

    if frozen
      show_thaw_items([input_plate1, input_plate2])
      shake(items: [input_plate1, input_plate2],
            speed: temporary_options[:shaker_parameters][:qty],
            time: temporary_options[:shaker_parameters][:qty])
      spin_down(items: [input_plate1, input_plate2],
                speed: temporary_options[:centrifuge_parameters][:speed],
                time: temporary_options[:centrifuge_parameters][:time])
    end

    get_and_label_new_plate(output_plate)

    adjust_volume(components: mm_components,
                  multi: adj_multi)

    create_master_mix(components: mm_components,
                     master_mix_item: mm.item,
                     adj_qty: true)

    label_items(objects: [composition.input(TEST_TUBE).input_name],
                labels: [mm.item])


    go_to_instrument(instrument_name: robot.model_and_name)

    robot.select_program_template(program: program)

    robot.save_run(path: program.run_file_path, file_name: file_name)

    robot.follow_template_instructions

    wait_for_instrument(instrument_name: robot.model_and_name)

    robot.remove_item(item: input_plate1)
    robot.remove_item(item: input_plate2)
    robot.remove_item(item: output_plate) 

    association_map = one_to_one_association_map(from_collection: input_plate1)

    copy_wells(from_collection: input_plate1,
               to_collection: output_plate,
               association_map: association_map)

    associate_transfer_collection_to_collection(from_collection: input_plate1,
                                                to_collection: output_plate,
                                                association_map: association_map,
                                                transfer_vol: composition.input(COV1).volume_hash)

    associate_transfer_collection_to_collection(from_collection: input_plate2,
                                                to_collection: output_plate,
                                                association_map: association_map,
                                                transfer_vol: composition.input(COV2).volume_hash)

    associate_transfer_item_to_collection(
      from_item: mm.item,
      to_collection: output_plate,
      association_map: association_map,
      transfer_vol: mm.volume_hash
    )

    seal_plate(output_plate, seal: composition.input(AREA_SEAL).input_name)

    shake(items: [output_plate],
          speed: temporary_options[:shaker_parameters][:speed],
          time: temporary_options[:shaker_parameters][:time])

    trash_object([input_plate1, input_plate2])
  end

  run_qpcr(operations: operations, item_key: POOLED_PLATE)

  {}

end

  def set_up_test(op)
    sample1 = op.input(COV1).part.sample
    sample2 = op.input(COV2).part.sample
    plate1 = op.input(COV1).collection
    plate2 = op.input(COV2).collection
    samples1 = Array.new(plate1.get_non_empty.length, sample1)
    samples2 = Array.new(plate2.get_non_empty.length, sample2)

    plate1.add_samples(samples1)
    plate2.add_samples(samples2)
  end


  # Redo this and actually check in a good way.  This makes me sad
  def check_if_frozen(plates)
    plates.each do |plate|
      location = plate.location
      return true if location.include? 'M80'
      return true if location.include? 'M20'
      return true if location.include? 'unknown'
      return true if debug
      return false
    end
  end
end
