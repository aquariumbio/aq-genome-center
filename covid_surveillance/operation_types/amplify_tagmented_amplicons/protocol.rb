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


#========== Composition Definitions ==========#

  AREA_SEAL = "Microseal 'B' adhesive seals"
  AMP_TAG_KIT = 'Amplify Tagmented Amplicons Kit'

  EPM_HT = 'Enhanced PCR Mix HT'
  IDT_PLATE = 'Index adapters'

  #======= Edited uyntil here

  MICRO_TUBES = '1.7 ml Tube'

  def components
    [ 
       {
         input_name: POOLED_PLATE,
         qty: nil, units: MICROLITERS,
         sample_name: 'Pooled Specimens',
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
        input_name: 'pipet_tip_100',
        qty: 2, units: 'Box',
        description: '100 ul Pipet Tips'
      }
    ]
  end

  def kits
    [
      {
        input_name: POST_TAG_KIT,
        qty: 1, units: 'kits',
        description: 'Kit for synthesizing first strand cDNA',
        location: 'M80 Freezer',
        components: [
          {
            input_name: ST2_HT,
            qty: 10, units: MICROLITERS,
            sample_name: ST2_HT,
            object_type: 'Reagent Bottle'
          },
          {
            input_name: TWB_HT,
            qty: 100, units: MICROLITERS,
            sample_name: TWB_HT,
            object_type: 'Reagent Bottle'
          }
        ],
        consumables: [
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
                            speed: create_qty(qty: 500, units: TIMES_G) },
    incubation_params: { time: create_qty(qty: 5, units: MINUTES),
                         temperature: create_qty(qty: 'room temperature',
                                                 units: '') }
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

  paired_ops.each do |op|
    set_up_test(op) if debug
    temporary_options = op.temporary[:options]

    composition = CompositionFactory.build(components: components,
                                           consumables: consumables,
                                           kits: kits)

    composition.input(POOLED_PLATE).item = op.input(POOLED_PLATE).collection
    plate = composition.input(POOLED_PLATE).item
    op.pass(POOLED_PLATE)

    show_get_composition(composition: composition)

    retrieve_materials([plate])

    vortex_objs(composition.kits.map { |kit|
      kit.composition.components.map(&:input_name)
    }.flatten)

    composition.make_kit_component_items

    association_map = one_to_one_association_map(from_collection: plate)
    kit = composition.input(POST_TAG_KIT)

    spin_down(items: [plate],
              speed: temporary_options[:centrifuge_parameters][:speed],
              time: temporary_options[:centrifuge_parameters][:time])

    multichannel_item_to_collection(to_collection: plate,
                                    source: kit.input(ST2_HT).item,
                                    volume: kit.input(ST2_HT).volume_hash,
                                    association_map: association_map,
                                    verbose: false)

    associate_transfer_item_to_collection(
      from_item: kit.input(ST2_HT).item,
      to_collection: plate,
      association_map: association_map,
      transfer_vol: kit.input(ST2_HT).volume_hash
    )

    seal_plate(plate, seal: composition.input(AREA_SEAL).input_name)

    shake(items: [plate],
          speed: temporary_options[:shaker_parameters][:speed],
          time: temporary_options[:shaker_parameters][:time])

    show_incubate_items(
      items: [plate],
      time: temporary_options[:incubation_params][:time],
      temperature: temporary_options[:incubation_params][:temperature]
    )

    spin_down(items: [plate],
              speed: temporary_options[:centrifuge_parameters][:speed],
              time: temporary_options[:centrifuge_parameters][:time])

    place_on_magnet(plate)

    if show_inspect_for_bubbles(plate)
      spin_down(items: [plate],
                speed: temporary_options[:centrifuge_parameters][:speed],
                time: temporary_options[:centrifuge_parameters][:time])
    end

    remove_discard_supernatant([plate])

    multichannel_item_to_collection(to_collection: plate,
                                    source: kit.input(TWB_HT).item,
                                    volume: kit.input(TWB_HT).volume_hash,
                                    association_map: association_map,
                                    verbose: false)

    seal_plate(plate, seal: composition.input(AREA_SEAL).input_name)

    shake(items: [plate],
          speed: temporary_options[:shaker_parameters][:speed],
          time: temporary_options[:shaker_parameters][:time])

    spin_down(items: [plate],
              speed: temporary_options[:centrifuge_parameters][:speed],
              time: temporary_options[:centrifuge_parameters][:time])

    place_on_magnet(plate)

    remove_discard_supernatant([plate])

    multichannel_item_to_collection(to_collection: plate,
                                    source: kit.input(TWB_HT).item,
                                    volume: kit.input(TWB_HT).volume_hash,
                                    association_map: association_map,
                                    verbose: false)

    associate_transfer_item_to_collection(
      from_item: kit.input(TWB_HT).item,
      to_collection: plate,
      association_map: association_map,
      transfer_vol: kit.input(TWB_HT).volume_hash
    )

    seal_plate(plate, seal: composition.input(AREA_SEAL).input_name)

    shake(items: [plate],
          speed: temporary_options[:shaker_parameters][:speed],
          time: temporary_options[:shaker_parameters][:time])

    spin_down(items: [plate],
              speed: temporary_options[:centrifuge_parameters][:speed],
              time: temporary_options[:centrifuge_parameters][:time])

    place_on_magnet(plate)

    store_items([plate], location: temporary_options[:storage_location])
  end

  {}

end

  # Instructions to place plate on some magnets
  #
  # @param plate [Collection]
  def place_on_magnet(plate)
    show do
      title 'Place on Magnetic Stand'
      note "Put plate #{plate} on magnetic stand and wait until clear (~3 Min)"
    end
  end

  def set_up_test(op)
    sample = op.input(POOLED_PLATE).part.sample
    plate = op.input(POOLED_PLATE).collection
    samples = Array.new(plate.get_empty.length, sample)
    plate.add_samples(samples)
  end

end
