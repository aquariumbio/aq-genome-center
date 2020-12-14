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
needs 'Covid Surveillance/CovidSurveillanceHelper'
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
  include CovidSurveillanceHelper

#========== Composition Definitions ==========#

  AREA_SEAL = "Microseal 'B' adhesive seals"
  AMP_TAG_KIT = 'Amplify Tagmented Amplicons Kit'

  EPM_HT = 'Enhanced PCR Mix HT'
  IDT_PLATE = 'Index Adapter'
  WATER = 'Nuclease-free water'

  TEST_TUBE = '15 ml Reagent Tube'

  SPARE_PLATE = '96 Well Plate'

  def components
    [ 
       {
         input_name: POOLED_PLATE,
         qty: nil, units: MICROLITERS,
         sample_name: 'Pooled Specimens',
         object_type: '96-Well Plate'
       },
       {
         input_name: WATER,
         qty: 24, units: MICROLITERS,
         sample_name: WATER,
         object_type: 'Reagent Bottle'
      },
      {
        input_name: MASTER_MIX,
        qty: 20, units: MICROLITERS,
        sample_name: MASTER_MIX,
        object_type: TEST_TUBE
      },
      {
        input_name: IDT_PLATE,
        qty: 10, units: MICROLITERS,
        sample_name: IDT_PLATE,
        object_type: '96-Well Plate'
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
        input_name: SPARE_PLATE,
        qty: 1, units: 'Each',
        description: '96 Well PCR Plate'
      },
      {
        input_name: 'pipet_tip_100',
        qty: 2, units: 'Box',
        description: '100 ul Pipet Tips'
      },
      {
        input_name: TEST_TUBE,
        qty: 1, units: 'Tubes',
        description: '15 ml Tube'
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
    robot_model: TestLiquidHandlingRobot::MODEL,
    storage_location: 'M80',
    shaker_parameters: { time: create_qty(qty: 1, units: MINUTES),
                         speed: create_qty(qty: 1600, units: RPM) },
    centrifuge_parameters: { time: create_qty(qty: 1, units: MINUTES),
                             speed: create_qty(qty: 500, units: TIMES_G) },
    incubation_params: { time: create_qty(qty: 5, units: MINUTES),
                         temperature: create_qty(qty: 'room temperature',
                                                 units: '') },
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

    operations.each do |op|
      set_up_test(op) if debug
      op.pass(POOLED_PLATE)

      temporary_options = op.temporary[:options]


      composition, kit = setup_kit_composition(
        kit_sample_name: AMP_TAG_KIT,
        num_reactions_required: op.input(POOLED_PLATE),
        components: components,
        consumables: consumables
      )

      composition.input(IDT_PLATE).sample.to_s

      composition.input(POOLED_PLATE).item = op.input(POOLED_PLATE).collection
      composition.input(IDT_PLATE).item = op.input(IDT_PLATE).collection

      plate = composition.input(POOLED_PLATE).item
      composition.input(WATER).item = find_random_item(
        sample: composition.input(WATER).sample,
        object_type: composition.input(WATER).object_type
      )

      mm = composition.input(MASTER_MIX)
      adj_multi = plate.get_non_empty.length
      mm_components = [composition.input(EPM_HT),
                       composition.input(WATER)]

      adjust_volume(components: mm_components,
                    multi: adj_multi)

      mm.item = make_item(sample: mm.sample,
                          object_type: mm.object_type)

      retrieve_list = reject_components(
        list_of_rejections: [MASTER_MIX],
        components: composition.components
      )
      show_retrieve_parts(retrieve_list + composition.consumables)

      vortex_list = reject_components(
        list_of_rejections: [POOLED_PLATE, WATER, IDT_PLATE],
        components: retrieve_list
      )

      show_block_1a = shake(items: vortex_list,
                            type: Vortex::NAME)

      adj_multiplier = plate.get_non_empty.length
      mm_components = [composition.input(EPM_HT), composition.input(WATER)]

      show_block_1b = master_mix_handler(components: mm_components,
                                         mm: composition.input(MASTER_MIX),
                                         adjustment_multiplier: adj_multiplier,
                                         mm_container: composition.input(TEST_TUBE))

      show_block_1c = place_on_magnet(plate)

      show_block_1d =remove_discard_supernatant([plate])

      show_block_1e = remove_from_magnet(plate)

      mm_program = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:robot_program]
      )

      robot = LiquidRobotFactory.build(model: temporary_options[:robot_model],
                                      name: op.temporary[:robot_model],
                                      protocol: self)

      show_block_1f = use_robot(program: mm_program, robot: robot, items: [plate, composition.input(MASTER_MIX), composition.input(IDT_PLATE)])

      association_map = one_to_one_association_map(from_collection: plate)

      associate_transfer_item_to_collection(
        from_item: mm.item,
        to_collection: plate,
        association_map: association_map,
        transfer_vol: mm.volume_hash
      )

      associate_transfer_collection_to_collection(
        from_collection: composition.input(IDT_PLATE).item,
        to_collection: plate,
        association_map: association_map,
        transfer_vol: composition.input(IDT_PLATE).volume_hash
      )

      transfer_adapter_index(from_plate: plate, to_plate: composition.input(IDT_PLATE).item)

      show_block_2a = []
      show_block_2a.append(seal_plate(
        [plate], seal: composition.input(AREA_SEAL).input_name
      ))

      show_block_2b = []
      show_block_2b.append(shake(
        items: [plate],
        speed: temporary_options[:shaker_parameters][:speed],
        time: temporary_options[:shaker_parameters][:time]
      ))

      show_block_2c = []
      show_block_2c.append(spin_down(
        items: [plate],
        speed: temporary_options[:centrifuge_parameters][:speed],
        time: temporary_options[:centrifuge_parameters][:time]
      ))

      show_block_2d = pipet_up_and_down(plate)

      show do
        title 'Prep and Run Robot'
        note show_block_1a
        separator
        note show_block_1b
        separator
        note show_block_1c
        separator
        note show_block_1d
        separator
        note show_block_1e
        separator
        note show_block_1f
      end

      show do
        title 'Prepare for Thermocycler'
        note show_block_2a
        separator
        note show_block_2b.flatten
        separator
        note show_block_2c.flatten
        separator
        note show_block_2d.flatten
      end

      run_qpcr(op: op,
               plates: [plate])
    end

    {}

  end

  def transfer_adapter_index(from_plate:, to_plate:)
    from_plate.parts.zip(to_plate.parts).each do |from, to|
      skip if from.nil? || to.nil?
      to_plate.associate(INDEX_KEY, from.get(INDEX_KEY))
    end
  end

  def set_up_test(op)
    [POOLED_PLATE, IDT_PLATE].each do |nam|
      sample = op.input(nam).part.sample
      plate = op.input(nam).collection
      samples = Array.new(plate.get_empty.length, sample)
      plate.add_samples(samples)
    end

    op.input(IDT_PLATE).collection.parts.each do |part|
      part.associate(INDEX_KEY, [1,2,3,4].sample)
    end
  end

end